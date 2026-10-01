import CryptoKit
import FPCore
import FPEngineClient
import Foundation

public actor CatalogStore: FontCataloging {
    private struct Working: Sendable {
        var files: [DiscoveredFile] = []
        var faces: [String: [FaceRecord]] = [:]
        var errors: [String: CatalogCache.Failure] = [:]
        var skipped: [(path: String, reason: SkipReason)] = []
        var folderIssues: [CatalogIssue] = []
        var menuVisible: Set<String> = []
        var registeredFaces: [RegisteredFaceInfo] = []
        func snapshot(complete: Bool, activity: CatalogActivity) -> CatalogSnapshot {
            CatalogBuilder.build(
                files: files, faces: faces, errors: errors.mapValues { ($0.code, $0.message) },
                skipped: skipped, folderIssues: folderIssues, menuVisible: menuVisible,
                registeredFaces: registeredFaces,
                generation: 0, isComplete: complete, activity: activity)
        }
    }
    private struct BatchResult: Sendable {
        var files: [DiscoveredFile]
        var faces: [String: [FaceRecord]] = [:]
        var errors: [String: CatalogCache.Failure] = [:]
    }
    private let engine: any EngineRunning
    private let registry: any SystemFontRegistry
    private let configuration: CatalogConfiguration
    private let centers: [NotificationCenter]
    private var folders: [URL] = []
    private var snapshot = CatalogSnapshot.empty
    private var working = Working()
    private var cache: CatalogCache?
    private var subscribers: [UUID: AsyncStream<CatalogSnapshot>.Continuation] = [:]
    private var active: Task<Void, Never>?
    private var activeWaiters: [UUID: CheckedContinuation<CatalogSnapshot, any Error>] = [:]
    private var queuedWaiters: [UUID: CheckedContinuation<CatalogSnapshot, any Error>] = [:]
    private var queuedMode: RefreshMode?
    private var observer: FontChangeObserver?
    private var debounce: Task<Void, Never>?
    private var lastFingerprint: String?
    private var changeGeneration = 0
    private(set) var refreshCount = 0

    public init(
        engine: any EngineRunning, registry: any SystemFontRegistry = CoreTextFontRegistry(),
        configuration: CatalogConfiguration, notificationCenters: [NotificationCenter]? = nil
    ) {
        self.engine = engine; self.registry = registry; self.configuration = configuration
        centers = notificationCenters ?? [NotificationCenter.default, DistributedNotificationCenter.default()]
    }
    public func currentSnapshot() -> CatalogSnapshot { snapshot }
    public func snapshots() -> AsyncStream<CatalogSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            subscribers[id] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in Task { await self?.removeSubscriber(id) } }
        }
    }
    private func removeSubscriber(_ id: UUID) { subscribers.removeValue(forKey: id) }
    private func publish(_ value: CatalogSnapshot) {
        var value = value; value.generation = snapshot.generation + 1; snapshot = value
        for continuation in subscribers.values { continuation.yield(value) }
    }
    public func extraFolders() -> [URL] { folders }
    public func setExtraFolders(_ values: [URL]) {
        var identities: Set<DiscoveredFileStamp.Identity> = []
        folders = values.filter { url in
            guard let stamp = DiscoveredFileStamp(url.path) else { return true }
            return identities.insert(stamp.identity).inserted
        }
    }
    public func refresh(_ mode: RefreshMode) async throws -> CatalogSnapshot {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if active == nil {
                    activeWaiters[id] = continuation
                    start(mode)
                } else {
                    queuedWaiters[id] = continuation
                    if queuedMode != .full { queuedMode = mode }
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }
    private func cancelWaiter(_ id: UUID) {
        activeWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        queuedWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
    private func start(_ mode: RefreshMode) {
        active = Task {
            let result: Result<CatalogSnapshot, any Error>
            do { result = .success(try await runRefresh(mode)) } catch { result = .failure(error) }
            finish(result)
        }
    }
    private func finish(_ result: Result<CatalogSnapshot, any Error>) {
        for waiter in activeWaiters.values { waiter.resume(with: result) }
        activeWaiters = [:]; active = nil
        if let mode = queuedMode {
            queuedMode = nil; activeWaiters = queuedWaiters; queuedWaiters = [:]
            start(mode)
        }
    }
    /// Cancels the running refresh and returns once it has wound down, so its helper process has stopped (NATIVE-7).
    public func cancelRefresh() async {
        guard let running = active else { return }
        running.cancel()
        for waiter in activeWaiters.values { waiter.resume(throwing: CancellationError()) }
        for waiter in queuedWaiters.values { waiter.resume(throwing: CancellationError()) }
        activeWaiters = [:]; queuedWaiters = [:]; queuedMode = nil
        await running.value
    }
    private func loadCache() async throws {
        if cache != nil { return }
        do {
            let hello = try await engine.hello()
            var value = CatalogCache(directory: configuration.cacheDirectory, readerVersion: hello.faceReaderVersion)
            value.load(); cache = value
        } catch is CancellationError { throw CancellationError() } catch {
            throw CatalogError.engineUnavailable(String(describing: error))
        }
    }
    private func saveCache() {
        do { try cache?.save() } catch { NSLog("Catalog cache save failed: %@", String(describing: error)) }
    }
    private func merge(_ batch: BatchResult) {
        for file in batch.files {
            working.faces[file.path] = batch.faces[file.path] ?? []
            working.errors[file.path] = batch.errors[file.path]
            cache?.put(file, faces: batch.faces[file.path] ?? [], error: batch.errors[file.path])
        }
    }
    private func runRefresh(_ mode: RefreshMode) async throws -> CatalogSnapshot {
        refreshCount += 1
        let previous = snapshot, oldWorking = working
        var oldCache = cache
        var completed: [DiscoveredFile] = []
        do {
            try await loadCache(); oldCache = cache; try Task.checkCancellation()
            let fingerprint = changeFingerprint()
            let discovery = FontDiscovery(registry: registry, configuration: configuration).discover(
                extraFolders: folders)
            working = Working(
                files: [], skipped: discovery.skipped, folderIssues: discovery.issues,
                menuVisible: discovery.menuVisible, registeredFaces: discovery.registeredFaces)
            var misses: [DiscoveredFile] = []
            for file in discovery.files {
                if mode == .incremental, let hit = cache?.hit(file) {
                    working.files.append(file); working.faces[file.path] = hit.faces;
                    working.errors[file.path] = hit.error
                } else if FontDiscovery.isSFNT(file.path) {
                    working.files.append(file); misses.append(file)
                } else {
                    if !working.skipped.contains(where: { $0.path == file.path && $0.reason == .unsupportedFormat }) {
                        working.skipped.append((file.path, .unsupportedFormat))
                    }
                }
            }
            var initial = previous
            initial.isComplete = false; initial.activity = .refreshing(.init(filesDone: 0, filesTotal: misses.count))
            publish(initial)
            var batches: [[DiscoveredFile]] = [], batch: [DiscoveredFile] = [], bytes: Int64 = 0
            for file in misses {
                if !batch.isEmpty
                    && (batch.count >= max(1, configuration.batchMaxFiles)
                        || bytes + file.stamp.size > configuration.batchMaxBytes)
                {
                    batches.append(batch); batch = []; bytes = 0
                }
                batch.append(file); bytes += file.stamp.size
            }
            if !batch.isEmpty { batches.append(batch) }
            let engine = self.engine
            var done = 0
            var lastPublish = ContinuousClock.now
            try await withThrowingTaskGroup(of: BatchResult.self) { group in
                var next = 0
                func enqueue() {
                    let files = batches[next]; next += 1
                    group.addTask { try await Self.scan(files, engine: engine) }
                }
                for _ in 0..<min(max(1, configuration.maxConcurrentScans), batches.count) { enqueue() }
                while let result = try await group.next() {
                    try Task.checkCancellation()
                    merge(result); completed += result.files; done += result.files.count
                    if done == misses.count || lastPublish.duration(to: .now) >= configuration.publishInterval {
                        let elapsed = lastPublish.duration(to: .now)
                        if elapsed < configuration.publishInterval {
                            try await Task.sleep(for: configuration.publishInterval - elapsed)
                        }
                        publish(
                            working.snapshot(
                                complete: false, activity: .refreshing(.init(filesDone: done, filesTotal: misses.count))
                            ))
                        lastPublish = .now
                    }
                    if next < batches.count { enqueue() }
                }
            }
            try Task.checkCancellation()
            let paths = Set(working.files.map(\.path))
            let pruned = cache?.entries.filter { paths.contains($0.key) } ?? [:]
            cache?.entries = pruned
            publish(working.snapshot(complete: true, activity: .idle)); saveCache(); lastFingerprint = fingerprint
            return snapshot
        } catch is CancellationError {
            // Keep the previous catalog visible and add only fully completed batches, but describe the system as this
            // refresh discovered it: menu visibility, disabled faces, skips and folder issues are already current.
            let partial = working
            working = oldWorking
            working.skipped = partial.skipped; working.folderIssues = partial.folderIssues
            working.menuVisible = partial.menuVisible; working.registeredFaces = partial.registeredFaces
            for file in completed {
                working.files.removeAll { $0.path == file.path || $0.stamp.identity == file.stamp.identity }
                working.files.append(file)
                working.faces[file.path] = partial.faces[file.path];
                working.errors[file.path] = partial.errors[file.path]
            }
            publish(working.snapshot(complete: false, activity: .idle)); saveCache()
            throw CancellationError()
        } catch {
            working = oldWorking; cache = oldCache
            var restored = previous; restored.activity = .idle; publish(restored)
            throw error
        }
    }
    private static func fatal(_ error: any Error) -> Bool {
        guard let error = error as? EngineError else { return false }
        return switch error {
        case .helperNotFound, .launchFailed, .incompatibleHelper: true;
        default: false
        }
    }
    private static func scan(_ files: [DiscoveredFile], engine: any EngineRunning) async throws -> BatchResult {
        var result = BatchResult(files: files)
        let paths = Set(files.map(\.path))
        do {
            for try await event in engine.scan(files: files.map(\.path)) {
                try Task.checkCancellation()
                switch event {
                case .face(let face): if paths.contains(face.path) { result.faces[face.path, default: []].append(face) }
                case .fileError(let error):
                    if paths.contains(error.path) {
                        result.errors[error.path] = .init(code: error.code.rawValue, message: error.message)
                    }
                default: break
                }
            }
            try Task.checkCancellation()
            for file in files where result.faces[file.path] == nil && result.errors[file.path] == nil {
                result.errors[file.path] = .init(code: "no_faces", message: "The font reader returned no faces.")
            }
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if fatal(error) { throw CatalogError.engineUnavailable(String(describing: error)) }
            let unresolved = files.filter { result.faces[$0.path] == nil && result.errors[$0.path] == nil }
            if files.count == 1 {
                if let file = unresolved.first {
                    result.errors[file.path] = .init(code: "helper_failed", message: String(describing: error))
                }
            } else if !unresolved.isEmpty {
                let middle = max(1, unresolved.count / 2)
                for half in [Array(unresolved.prefix(middle)), Array(unresolved.dropFirst(middle))] where !half.isEmpty
                {
                    let retry = try await scan(half, engine: engine)
                    result.faces.merge(retry.faces) { _, new in new };
                    result.errors.merge(retry.errors) { _, new in new }
                }
            }
        }
        return result
    }
    public func noteInstalled(_ fileURL: URL) async throws -> CatalogSnapshot {
        while let active { await active.value }
        let path = fileURL.standardizedFileURL.path
        guard let stamp = DiscoveredFileStamp(path) else { throw CocoaError(.fileNoSuchFile) }
        try await loadCache()
        let registered = working.files.contains {
            $0.stamp.identity == stamp.identity && ($0.origin == .activated || !$0.registeredPostscriptNames.isEmpty)
        }
        let file = DiscoveredFile(
            path: path,
            origin: .classify(
                path: path,
                isInsideUserFolder: DiscoveredFileStamp.inside(
                    URL(fileURLWithPath: path), folder: configuration.userFontsFolder),
                isRegistered: registered), stamp: stamp, registeredPostscriptNames: [])
        let result: BatchResult
        if let entry = cache?.hit(file) {
            result = BatchResult(
                files: [file], faces: [path: entry.faces], errors: entry.error.map { [path: $0] } ?? [:])
        } else {
            do { result = try await Self.scan([file], engine: engine) } catch {
                result = BatchResult(
                    files: [file], errors: [path: .init(code: "helper_failed", message: String(describing: error))])
            }
        }
        working.files.removeAll { $0.stamp.identity == stamp.identity || $0.path == path }
        working.files.append(file); merge(result)
        working.menuVisible.formUnion((result.faces[path] ?? []).compactMap(\.postscriptName))
        publish(working.snapshot(complete: true, activity: .idle)); saveCache(); return snapshot
    }
    public func noteRemoved(_ fileURL: URL) async -> CatalogSnapshot {
        while let active { await active.value }
        let path = fileURL.standardizedFileURL.path, identity = DiscoveredFileStamp(fileURL.path)?.identity
        let removed = working.files.filter { $0.path == path || (identity != nil && $0.stamp.identity == identity) }
        let paths = Set(removed.map(\.path))
        working.files.removeAll { paths.contains($0.path) }
        for key in paths {
            working.faces.removeValue(forKey: key); working.errors.removeValue(forKey: key);
            cache?.entries.removeValue(forKey: key)
        }
        publish(working.snapshot(complete: snapshot.isComplete, activity: .idle)); saveCache(); return snapshot
    }
    public func startObservingSystemChanges() {
        guard observer == nil else { return }
        observer = FontChangeObserver(centers: centers) { [weak self] in Task { await self?.systemFontsChanged() } }
    }
    public func stopObservingSystemChanges() {
        observer?.stop(); observer = nil; debounce?.cancel(); debounce = nil; changeGeneration += 1
    }
    func systemFontsChanged() {
        changeGeneration += 1
        let generation = changeGeneration, delay = configuration.changeDebounce
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: delay); await self?.refreshForChange(generation) } catch {}
        }
    }
    private func refreshForChange(_ generation: Int) async {
        guard generation == changeGeneration, changeFingerprint() != lastFingerprint else { return }
        do { _ = try await refresh(.incremental) } catch {
            NSLog("Catalog refresh failed: %@", String(describing: error))
        }
    }
    private func changeFingerprint() -> String {
        let paths: [String], disabled: [String]
        if let coreText = registry as? CoreTextFontRegistry {
            let value = coreText.fingerprintSnapshot(); paths = value.paths; disabled = value.disabledNames
        } else {
            paths = registry.registeredFontFiles().map(\.path)
            disabled = registry.registeredFaces(includeDisabled: true).filter { !$0.enabled }.map(\.postscriptName)
        }
        var lines = paths.sorted().map { path in
            guard let stamp = DiscoveredFileStamp(path) else { return "\(path)|-1|-1" }
            return "\(path)|\(stamp.size)|\(stamp.mtime)"
        }
        lines += (configuration.standardFolders + folders).map {
            "\($0.path)|\(DiscoveredFileStamp($0.path)?.mtime ?? -1)"
        }
        lines += disabled.sorted()
        return SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
