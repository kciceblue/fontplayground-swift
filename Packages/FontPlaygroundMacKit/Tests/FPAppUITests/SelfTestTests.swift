import FPCore
import FPEngineClient
import Foundation
import Testing

@testable import FPAppUI

struct SelfTestTests {
    @Test func passesWithAHealthyFakeEngine() async throws {
        let test = try SelfTestFixture(); defer { test.remove() }
        let result = await test.run()
        #expect(result.exitCode == 0)
        #expect(result.summary.result == "passed")
        #expect(result.summary.engine == "embedded")
        #expect(result.summary.failedSteps.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: test.runRoot.path))
        let lines = try test.output.objects()
        #expect(lines.count == 10)
        #expect(lines.dropLast().compactMap { $0["step"] as? String } == SelfTestStep.allCases.map(\.rawValue))
        for line in lines.dropLast() {
            #expect(line["ok"] as? Bool == true)
            #expect(line["duration_ms"] is Int)
            #expect(line["detail"] is [String: String])
            #expect(line["error"] is NSNull)
        }
        #expect(lines.last?["type"] as? String == "summary")
        #expect(
            test.output.lines[0].hasPrefix("{\"type\":\"step\",\"step\":\"environment\",\"ok\":true,\"duration_ms\":"))
        #expect(test.engine.scanned == test.faces.map(\.path))
    }

    @Test func stopsAtFirstFailureButCleansUp() async throws {
        let test = try SelfTestFixture(mode: .failure); defer { test.remove() }
        let result = await test.run()
        #expect(result.exitCode == 1)
        #expect(result.summary.failedSteps == ["forge"])
        let steps = try test.output.objects().compactMap { $0["step"] as? String }
        #expect(steps == ["environment", "engine", "recipe", "discover", "scan", "forge", "cleanup"])
        #expect(!FileManager.default.fileExists(atPath: test.runRoot.path))
    }

    @Test func wrongBundleIdFailsEnvironment() async throws {
        let test = try SelfTestFixture(); defer { test.remove() }
        var dependencies = test.dependencies
        dependencies.bundleInfo = { .init(identifier: "com.example.other", shortVersion: "0.1.0", build: "1") }
        let result = await test.run(dependencies: dependencies)
        #expect(result.exitCode == 1)
        #expect(result.summary.failedSteps == ["environment"])
        #expect(test.engine.forgeCount == 0)
    }

    @Test func requireEmbeddedEngineRejectsDevEngine() async throws {
        let test = try SelfTestFixture(); defer { test.remove() }
        var dependencies = test.dependencies
        dependencies.engine = { _ in (test.engine, .dev) }
        let result = await test.run(options: .init(requireEmbeddedEngine: true), dependencies: dependencies)
        #expect(result.exitCode == 3)
        #expect(result.summary.engine == "dev")
        #expect(result.summary.failedSteps == ["engine"])
    }

    @Test func noEngineIsAnEnvironmentError() async throws {
        let test = try SelfTestFixture(); defer { test.remove() }
        var dependencies = test.dependencies
        dependencies.engine = { _ in throw EngineError.helperNotFound(searched: []) }
        let result = await test.run(dependencies: dependencies)
        #expect(result.exitCode == 3)
        #expect(result.summary.engine == "none")
    }

    @Test func tooling14CancelMustEndTheHelperWithinThreeSeconds() async throws {
        for delay in [0.5, 5.0] {
            let test = try SelfTestFixture(endDelay: delay); defer { test.remove() }
            let start = ContinuousClock.now
            let result = await test.run()
            #expect(result.exitCode == (delay < 3 ? 0 : 1))
            if delay > 3 {
                #expect(result.summary.failedSteps == ["cancel"])
                #expect(start.duration(to: .now) >= .seconds(3))
                #expect(start.duration(to: .now) < .seconds(4.5))
            }
        }
        let test = try SelfTestFixture(); defer { test.remove() }
        var dependencies = test.dependencies
        dependencies.helperProcessIDs = { [] }
        let result = await test.run(dependencies: dependencies)
        #expect(result.exitCode == 1)
        #expect(result.summary.failedSteps == ["cancel"])
        #expect(test.output.lines.contains { $0.contains("no helper child process was seen") })
    }

    @Test func injectedFailureFailsThatStep() async throws {
        let test = try SelfTestFixture(); defer { test.remove() }
        var dependencies = test.dependencies
        dependencies.injectedFailure = "verify"
        let result = await test.run(dependencies: dependencies)
        #expect(result.exitCode == 1)
        #expect(result.summary.failedSteps == ["verify"])
        #expect(test.output.lines.contains { $0.contains("\"error\":\"injected\"") })
    }

    @Test func overallTimeoutReturnsFour() async throws {
        let test = try SelfTestFixture(mode: .hang); defer { test.remove() }
        let start = ContinuousClock.now
        let result = await test.run(options: .init(timeout: .seconds(10)))
        #expect(result.exitCode == 4)
        #expect(result.summary.result == "timed_out")
        #expect(start.duration(to: .now) < .seconds(12))
        #expect(!FileManager.default.fileExists(atPath: test.runRoot.path))
    }

    @Test func stepBudgetCancelsEngineBeforeOverallDeadline() async throws {
        let test = try SelfTestFixture(mode: .slowHello); defer { test.remove() }
        let start = ContinuousClock.now
        let result = await test.run()
        #expect(result.exitCode == 1)
        #expect(result.summary.failedSteps == ["engine"])
        #expect(test.engine.helloCancelled)
        #expect(start.duration(to: .now) >= .seconds(20))
        #expect(start.duration(to: .now) < .seconds(22))
        #expect(test.output.lines.contains { $0.contains("step budget of 20 s exceeded") })
        #expect(!FileManager.default.fileExists(atPath: test.runRoot.path))
    }

    @Test func overallDeadlineDoesNotWaitForANonCooperativeHello() async throws {
        let test = try SelfTestFixture(); defer { test.remove() }
        let gate = SelfTestHeldDependency(); defer { gate.release() }
        var dependencies = test.dependencies
        dependencies.engine = { _ in (SelfTestHeldHello(base: test.engine, gate: gate), .embedded) }
        let started = ContinuousClock.now
        let result = await test.run(options: .init(timeout: .seconds(10)), dependencies: dependencies)
        #expect(gate.entered && !gate.returned)
        #expect(result.exitCode == 4 && result.summary.result == "timed_out")
        #expect(started.duration(to: .now) >= .seconds(10) && started.duration(to: .now) < .seconds(12))
        #expect(!FileManager.default.fileExists(atPath: test.runRoot.path))
        let lines = test.output.lines
        gate.release(); try await gate.waitUntilReturned()
        try await Task.sleep(for: .milliseconds(100))
        #expect(test.output.lines == lines)
        #expect(try test.output.objects().last?["type"] as? String == "summary")
        #expect(test.engine.forgeCount == 0)
    }

    @Test func stepDeadlineDoesNotWaitForASynchronousDependency() async throws {
        let test = try SelfTestFixture(); defer { test.remove() }
        let gate = SelfTestHeldDependency(); defer { gate.release() }
        var dependencies = test.dependencies
        dependencies.recipeData = { gate.hold { test.data } }
        let started = ContinuousClock.now
        let result = await test.run(dependencies: dependencies)
        #expect(gate.entered && !gate.returned)
        #expect(result.exitCode == 1 && result.summary.failedSteps == ["recipe"])
        #expect(started.duration(to: .now) >= .seconds(1) && started.duration(to: .now) < .seconds(3))
        #expect(test.output.lines.contains { $0.contains("step budget of 1 s exceeded") })
        #expect(!FileManager.default.fileExists(atPath: test.runRoot.path))
        let lines = test.output.lines
        gate.release(); try await gate.waitUntilReturned()
        try await Task.sleep(for: .milliseconds(100))
        #expect(test.output.lines == lines && test.engine.forgeCount == 0)
    }

    @Test func overallDeadlineIncludesSetupAndRemovesALateRoot() async throws {
        let test = try SelfTestFixture(); defer { test.remove() }
        let gate = SelfTestHeldDependency(); defer { gate.release() }
        var dependencies = test.dependencies
        dependencies.temporaryRoot = {
            try gate.hold {
                try FileManager.default.createDirectory(at: test.runRoot, withIntermediateDirectories: true)
                return test.runRoot
            }
        }
        let started = ContinuousClock.now
        let result = await test.run(options: .init(timeout: .milliseconds(100)), dependencies: dependencies)
        #expect(gate.entered && !gate.returned)
        #expect(result.exitCode == 4 && result.summary.failedSteps.isEmpty)
        #expect(started.duration(to: .now) < .seconds(2))
        #expect(test.output.lines.count == 1)
        let lines = test.output.lines
        gate.release(); try await gate.waitUntilReturned()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while FileManager.default.fileExists(atPath: test.runRoot.path) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!FileManager.default.fileExists(atPath: test.runRoot.path))
        #expect(test.output.lines == lines && test.engine.forgeCount == 0)
    }

    @Test func cleanupCannotExtendAnOverallTimeoutByFiveSeconds() async throws {
        let test = try SelfTestFixture(mode: .hang); defer { test.remove() }
        let gate = SelfTestHeldDependency(); defer { gate.release() }
        var dependencies = test.dependencies
        dependencies.removeTemporaryRoot = { root in
            try gate.hold { try FileManager.default.removeItem(at: root) }
        }
        let started = ContinuousClock.now
        let result = await test.run(options: .init(timeout: .milliseconds(200)), dependencies: dependencies)
        #expect(gate.entered && !gate.returned)
        // The 200 ms timeout plus the 1.5 s cleanup grace takes about 1.7 s; the ordinary 5 s cleanup budget would
        // take over 5.2 s. Four seconds tells them apart with room for the Mac mini's coarse timers (testing.md).
        #expect(result.exitCode == 4 && started.duration(to: .now) < .seconds(4))
        let cleanup = try #require(try test.output.objects().first { $0["step"] as? String == "cleanup" })
        #expect(cleanup["ok"] as? Bool == false)
        #expect(cleanup["error"] as? String == "cleanup budget exceeded")
        let lines = test.output.lines
        gate.release(); try await gate.waitUntilReturned()
        #expect(!FileManager.default.fileExists(atPath: test.runRoot.path))
        #expect(test.output.lines == lines)
    }

    @Test func tooling14BlockedProcessLookupStillCancelsTheWorker() async throws {
        let test = try SelfTestFixture(endDelay: 0); defer { test.remove() }
        let gate = SelfTestHeldDependency(); defer { gate.release() }
        var dependencies = test.dependencies
        dependencies.helperProcessIDs = {
            if test.engine.forgeCount >= 2 { return gate.hold { test.engine.processIDs } }
            return test.engine.processIDs
        }
        let result = await test.run(options: .init(timeout: .seconds(1)), dependencies: dependencies)
        #expect(result.exitCode == 4 && gate.entered && !gate.returned)
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !test.engine.processIDs.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(test.engine.forgeCount == 2 && test.engine.processIDs.isEmpty)
        let lines = test.output.lines
        gate.release(); try await gate.waitUntilReturned()
        try await Task.sleep(for: .milliseconds(100))
        #expect(test.output.lines == lines)
    }

    @Test func deadlineRaceHandlesCancellationBeforeContinuationInstallation() async throws {
        let started = ContinuousClock.now
        for _ in 0..<200 {
            let worker = Task {
                try await selfTestDeadline(.seconds(60)) {
                    try await Task.sleep(for: .seconds(60))
                    return 1
                }
            }
            worker.cancel()
            do {
                _ = try await worker.value
                Issue.record("A cancelled deadline race unexpectedly succeeded")
            } catch {
                #expect(error is CancellationError)
            }
        }
        #expect(started.duration(to: .now) < .seconds(3))
    }

    @Test func usageErrors() throws {
        for arguments in [
            ["--self-test-timeout", "abc"], ["--self-test-timeout", "5"], ["--self-test-bogus"],
            ["--self-test-report"], ["--self-test-timeout"], ["--self-test-timeout", "3601"],
        ] {
            #expect(throws: SelfTestUsageError.self) { try SelfTestOptions.parse(arguments) }
        }
        let options = try SelfTestOptions.parse([
            "app", "--self-test", "--self-test-keep", "--require-embedded-engine", "--self-test-timeout", "42",
            "--self-test-report", "/tmp/example.jsonl",
        ])
        #expect(options.keepTemporaryFiles && options.requireEmbeddedEngine)
        #expect(options.timeout == .seconds(42))
        #expect(options.reportURL?.path == "/tmp/example.jsonl")
    }

    @Test func selfTestRecipeDecodes() throws {
        let url = try #require(Bundle.module.url(forResource: "self-test", withExtension: "fontrecipe"))
        let recipe = try RecipeDocument.decode(Data(contentsOf: url))
        #expect(recipe.materials.count == 2)
        #expect(recipe.main == 0)
        #expect(recipe.rules == [.symbols: 1])
        #expect(recipe.materials.map(\.face.postscriptName) == ["Georgia", "Menlo-Regular"])
    }

    @Test func crit1NoCompatibilityKeyInInfoPlist() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try #require(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: repo.appendingPathComponent("App/Info.plist")), format: nil) as? [String: Any])
        #expect(plist["UIDesignRequiresCompatibility"] == nil)
        #expect(plist["NSRequiresAquaSystemAppearance"] == nil)
    }

    @Test func missingDiscoveryPathIsReported() async throws {
        let test = try SelfTestFixture(); defer { test.remove() }
        var dependencies = test.dependencies
        dependencies.availableFontURLs = { [] }
        let result = await test.run(dependencies: dependencies)
        #expect(result.summary.failedSteps == ["discover"])
        let line = try #require(try test.output.objects().first { $0["step"] as? String == "discover" })
        #expect((line["detail"] as? [String: String])?["missing"]?.contains(test.faces[0].path) == true)
    }

    @Test func tempRootFailureEmitsOnlySummary() async throws {
        let test = try SelfTestFixture(); defer { test.remove() }
        var dependencies = test.dependencies
        dependencies.temporaryRoot = { throw CocoaError(.fileWriteNoPermission) }
        let result = await test.run(dependencies: dependencies)
        #expect(result.exitCode == 3)
        #expect(result.summary.failedSteps.isEmpty)
        #expect(test.output.lines.count == 1)
    }

    @Test func keepAndCleanupFailureDoNotChangeSuccess() async throws {
        for keep in [true, false] {
            let test = try SelfTestFixture(); defer { test.remove() }
            var dependencies = test.dependencies
            if !keep { dependencies.injectedFailure = "cleanup" }
            let result = await test.run(options: .init(keepTemporaryFiles: keep), dependencies: dependencies)
            #expect(result.exitCode == 0)
            #expect(result.summary.failedSteps.isEmpty)
            #expect(FileManager.default.fileExists(atPath: test.runRoot.path))
            let cleanup = try #require(try test.output.objects().first { $0["step"] as? String == "cleanup" })
            #expect(cleanup["ok"] as? Bool == keep)
            if keep { #expect((cleanup["detail"] as? [String: String])?["root"] == test.runRoot.path) }
        }
    }
}

private struct SelfTestFixture: Sendable {
    let root: URL
    let runRoot: URL
    let faces: [FaceRecord]
    let data: Data
    let engine: SelfTestFakeEngine
    let output = SelfTestCapturedLines()
    init(mode: SelfTestFakeEngine.Mode = .healthy, endDelay: Double = 0.2) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("self-test-tests-\(UUID())")
        runRoot = root.appendingPathComponent("run")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceRoot = root
        faces = ["One", "Two"].enumerated().map { index, name in
            FaceRecord(
                path: sourceRoot.appendingPathComponent("\(name).ttf").path, family: name,
                coverage: CodepointSet([65 + UInt32(index)]), postscriptName: name)
        }
        var recipe = Recipe()
        faces.forEach { _ = recipe.add($0) }
        _ = recipe.setSampleText("AB")
        data = try RecipeDocument(recipe: recipe).encoded()
        engine = SelfTestFakeEngine(faces: faces, mode: mode, endDelay: endDelay)
    }
    var dependencies: SelfTestDependencies {
        .init(
            bundleInfo: { .init(identifier: "io.github.kciceblue.fontplayground", shortVersion: "0.1.0", build: "1") },
            engine: { _ in (engine, .embedded) }, availableFontURLs: { faces.map { URL(fileURLWithPath: $0.path) } },
            checkBuiltFont: { _, name, sample in
                .init(postScriptName: name, mappedCharacters: sample.utf16.count, hasForgedMarker: true)
            },
            recipeData: { data }, temporaryRoot: { runRoot }, helperProcessIDs: { engine.processIDs },
            injectedFailure: nil)
    }
    func run(options: SelfTestOptions = .init(), dependencies: SelfTestDependencies? = nil) async -> (
        summary: SelfTestSummary, exitCode: Int32
    ) {
        await SelfTestRunner(
            options: options, dependencies: dependencies ?? self.dependencies, output: { output.append($0) }
        ).run()
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class SelfTestCapturedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var lines: [String] { lock.withLock { values } }
    func append(_ line: String) { lock.withLock { values.append(line) } }
    func objects() throws -> [[String: Any]] {
        try lines.map { try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    }
}

private final class SelfTestFakeEngine: EngineRunning, @unchecked Sendable {
    enum Mode: Sendable { case healthy, failure, hang, slowHello }
    let faces: [FaceRecord], mode: Mode, endDelay: Double
    private let lock = NSLock()
    private var count = 0
    private var cancelled: ContinuousClock.Instant?
    private var scanPaths: [String] = []
    private var helloWasCancelled = false
    init(faces: [FaceRecord], mode: Mode, endDelay: Double) {
        self.faces = faces; self.mode = mode; self.endDelay = endDelay
    }
    var forgeCount: Int { lock.withLock { count } }
    var scanned: [String] { lock.withLock { scanPaths } }
    var helloCancelled: Bool { lock.withLock { helloWasCancelled } }
    var processIDs: Set<Int32> {
        lock.withLock {
            guard count >= 2 else { return [] }
            if let cancelled, cancelled.duration(to: .now) >= .seconds(endDelay) { return [] }
            return [4242]
        }
    }
    func hello() async throws -> EngineHello {
        if mode == .slowHello {
            do { try await Task.sleep(for: .seconds(30)) } catch {
                lock.withLock { helloWasCancelled = true }; throw error
            }
        }
        return .init(
            fpengineVersion: "0.1.0", python: "3.12", fonttools: "4", platform: "fake", capabilities: ["scan", "forge"])
    }
    func scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error> {
        lock.withLock { scanPaths = files }
        return AsyncThrowingStream { stream in
            faces.forEach { stream.yield(.face($0)) }
            stream.yield(.finished(.init(files: files.count, faces: faces.count, fileErrors: 0, duplicates: 0)))
            stream.finish()
        }
    }
    func forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error> {
        let call = lock.withLock {
            count += 1; return count
        }
        return AsyncThrowingStream { stream in
            if mode == .failure {
                stream.finish(
                    throwing: EngineError.helperFailed(
                        .init(code: .unsupportedFont, stage: .validate, message: "fake failure")))
            } else if call == 1 && mode == .healthy {
                do {
                    try AtomicFile.write(Data([1]), to: request.outputPath)
                    stream.yield(.progress(.init(stage: .done, fraction: 1)))
                    stream.yield(
                        .finished(
                            .init(
                                outputPath: request.outputPath, postscriptName: "FPTest-Regular", totalCodepoints: 2,
                                totalGlyphs: 3)))
                    stream.finish()
                } catch { stream.finish(throwing: error) }
            } else {
                stream.onTermination = { [self] _ in lock.withLock { cancelled = .now } }
                stream.yield(.progress(.init(stage: .prepare, fraction: 0.1)))
            }
        }
    }
}

/// Release only after the runner has returned: cancellation deliberately cannot unblock this dependency.
private final class SelfTestHeldDependency: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false, didEnter = false, didReturn = false
    var entered: Bool { condition.withLock { didEnter } }
    var returned: Bool { condition.withLock { didReturn } }
    func hold<Value>(_ body: () throws -> Value) rethrows -> Value {
        condition.lock(); didEnter = true
        while !released { condition.wait() }
        condition.unlock()
        defer { condition.withLock { didReturn = true } }
        return try body()
    }
    func release() {
        condition.withLock {
            released = true; condition.broadcast()
        }
    }
    func waitUntilReturned() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !returned && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(returned)
    }
}

private final class SelfTestHeldHello: EngineRunning, Sendable {
    let base: SelfTestFakeEngine, gate: SelfTestHeldDependency
    init(base: SelfTestFakeEngine, gate: SelfTestHeldDependency) { self.base = base; self.gate = gate }
    func hello() async throws -> EngineHello {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [gate] in
                gate.hold { continuation.resume() }
            }
        }
        return try await base.hello()
    }
    func scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error> { base.scan(files: files) }
    func forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error> { base.forge(request) }
}
