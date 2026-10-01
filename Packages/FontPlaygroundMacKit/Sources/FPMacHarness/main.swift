import Darwin
import FPEngineClient
import FPMacServices
import Foundation

@main
struct MacHarness {
    static func main() async { exit(await run()) }
    static func run(
        arguments: [String] = Array(CommandLine.arguments.dropFirst()),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fontBook: FontBookLauncher = FontBookLauncher(),
        output: @escaping @Sendable (String) -> Void = { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
        errorOutput: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) async -> Int32 {
        var args = arguments
        let usage =
            "Usage: fpmac-harness fontbook | catalog [--extra <dir>] [--cache-dir <dir>] [--python <path>] [--check] [--watch]"
        if args.first == "fontbook" {
            guard args.count == 1 else { errorOutput(usage); return 2 }
            do {
                try await fontBook.open()
                output("opened Font Book")
                return 0
            } catch let error as FontBookError {
                errorOutput(error.englishText)
                return 1
            } catch {
                errorOutput(error.localizedDescription)
                return 1
            }
        }
        guard args.first == "catalog" else { errorOutput(usage); return 2 }
        args.removeFirst()
        var extra: [URL] = [], cacheDirectory: URL?, python = environment["FP_ENGINE_PYTHON"]
        var check = false, watch = false
        while !args.isEmpty {
            let option = args.removeFirst()
            if option == "--check" { check = true; continue }
            if option == "--watch" { watch = true; continue }
            guard ["--extra", "--cache-dir", "--python"].contains(option), !args.isEmpty else {
                errorOutput(usage); return 2
            }
            let value = args.removeFirst()
            switch option {
            case "--extra": extra.append(URL(fileURLWithPath: value))
            case "--cache-dir": cacheDirectory = URL(fileURLWithPath: value)
            default: python = value
            }
        }
        guard let python, !python.isEmpty else { errorOutput("Set FP_ENGINE_PYTHON or pass --python."); return 2 }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("fpmac-harness-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            let launch = try EngineLaunch.resolve(environment: ["FP_ENGINE_PYTHON": python], bundleURL: nil)
            let engine = EngineClient(configuration: EngineConfiguration(launch: launch, temporaryDirectory: temporary))
            var configuration = CatalogConfiguration.standard()
            configuration.cacheDirectory = cacheDirectory ?? temporary.appendingPathComponent("cache")
            let registry = CoreTextFontRegistry()
            let store = CatalogStore(engine: engine, registry: registry, configuration: configuration)
            await store.setExtraFolders(extra)
            let start = ContinuousClock.now
            let snapshot = try await store.refresh(.incremental)
            for line in CatalogReport.lines(for: snapshot) { output(line) }
            let elapsed = start.duration(to: .now).components
            output(String(format: "elapsed=%.2f", Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18))
            let problems =
                check ? CatalogReport.check(snapshot, menuVisible: registry.menuVisiblePostScriptNames()) : []
            for problem in problems { output("problem: \(problem)") }
            if !problems.isEmpty { return 1 }
            if watch { return await watchCatalog(store, after: snapshot, output: output) }
            return 0
        } catch {
            errorOutput(String(describing: error))
            return 1
        }
    }

    private static func watchCatalog(
        _ catalog: any FontCataloging, after snapshot: CatalogSnapshot,
        output: @escaping @Sendable (String) -> Void
    ) async -> Int32 {
        let previousHandler = signal(SIGINT, SIG_IGN)
        let task = Task { await CatalogWatch.run(catalog: catalog, after: snapshot, output: output) }
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        interrupt.setEventHandler { task.cancel() }
        interrupt.resume()
        defer { interrupt.cancel(); signal(SIGINT, previousHandler) }
        let cancelled = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        return cancelled ? 130 : 0
    }
}
