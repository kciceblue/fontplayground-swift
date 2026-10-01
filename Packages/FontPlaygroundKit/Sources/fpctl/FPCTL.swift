import FPCore
import FPEngineClient
import Foundation

struct EngineHandle: Sendable {
    var engine: any EngineRunning
    var helper: String
    var temporaryDirectory: URL?
}

@main struct FPCTL {
    static let version = "1.0.0"
    static let usage = """
        Usage: fpctl [--engine <python>] [--verbose] <command> [options]

        Commands:
          hello                        Show the font engine's version.
          scan <file|folder>...        Read fonts and list their faces.
          forge <recipe.fontrecipe> --out <file.ttf>
                                       Build the font a recipe describes.

        Options:
          --engine <python>            Python that can run fpengine (default: $FP_ENGINE_PYTHON).
          --verbose                    Show the engine's log on stderr.
          --json                       Print JSON instead of text.
          --font-dir <folder>          forge: where to look for fonts the recipe can't find. Repeatable.
          --allow-missing              forge: build without fonts that can't be found.
          --quiet                      forge: don't print progress.
          -h, --help                   Show this help.
          --version                    Show fpctl's version.

        Exit status: 0 success, 1 the engine reported an error, 2 usage or input error,
        3 the engine could not run, 4 fonts not found, 130 interrupted.
        """
    private static let taskBox = TaskBox()
    static func main() async {
        signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
        let sources = [SIGINT, SIGTERM].map { value in
            let source = DispatchSource.makeSignalSource(signal: value, queue: .global())
            source.setEventHandler { interrupt() }
            source.resume()
            return source
        }
        let status = await run(
            Array(CommandLine.arguments.dropFirst()), environment: ProcessInfo.processInfo.environment,
            currentDirectory: FileManager.default.currentDirectoryPath,
            output: CommandOutput(
                out: { try? FileHandle.standardOutput.write(contentsOf: Data(($0 + "\n").utf8)) },
                err: { try? FileHandle.standardError.write(contentsOf: Data(($0 + "\n").utf8)) }))
        sources.forEach { $0.cancel() }
        exit(status)
    }
    static func run(
        _ arguments: [String], environment: [String: String], currentDirectory: String, output: CommandOutput,
        makeEngine: @escaping @Sendable (Invocation, [String: String], CommandOutput) throws -> EngineHandle = FPCTL
            .defaultEngine
    ) async -> Int32 {
        let invocation: Invocation
        do { invocation = try parse(arguments, currentDirectory: currentDirectory) } catch {
            output.err("fpctl: \(error.message)")
            output.err("Run 'fpctl --help' for usage.")
            return 2
        }
        switch invocation.command {
        case .help: output.out(usage); return 0
        case .version: output.out("fpctl \(version)"); return 0
        default: break
        }
        taskBox.begin()
        let task = Task<Int32, Never> {
            do {
                try Task.checkCancellation()
                let document: RecipeDocument?
                if case .forge(let path, _, _, _, _, _) = invocation.command {
                    let data: Data
                    do { data = try Data(contentsOf: URL(fileURLWithPath: path)) } catch {
                        output.err("fpctl: \(path): \(error.localizedDescription)"); return 2
                    }
                    do { document = try RecipeDocument.decode(data) } catch {
                        output.err("fpctl: \(path): not a valid Font Playground recipe (\(error))"); return 2
                    }
                } else {
                    document = nil
                }
                let handle = try makeEngine(invocation, environment, output)
                return try await execute(
                    invocation, environment: environment, handle: handle, output: output, document: document)
            } catch {
                if Task.isCancelled { return 130 }
                return report(error, invocation: invocation, output: output)
            }
        }
        taskBox.install(task)
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            interrupt()
        }
        return taskBox.finish() ? 130 : result
    }
    static func interrupt() { taskBox.cancel() }
    static func defaultEngine(_ invocation: Invocation, _ environment: [String: String], _ output: CommandOutput) throws
        -> EngineHandle
    {
        let launch: EngineLaunch
        if let path = invocation.enginePath {
            launch = EngineLaunch(executableURL: URL(fileURLWithPath: path))
        } else {
            launch = try EngineLaunch.resolve(environment: environment, bundleURL: nil)
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(
            "fpctl", isDirectory: true)
        let engine = EngineClient(
            configuration: EngineConfiguration(
                launch: launch, temporaryDirectory: directory,
                logHandler: invocation.verbose ? output.err : nil))
        return EngineHandle(
            engine: engine, helper: ([launch.executableURL.path] + launch.arguments).joined(separator: " "),
            temporaryDirectory: directory)
    }
    private static func report(_ error: any Error, invocation: Invocation, output: CommandOutput) -> Int32 {
        if let engine = error as? EngineError {
            switch engine {
            case .helperNotFound:
                output.err("fpctl: can't find the font engine; set FP_ENGINE_PYTHON or pass --engine")
            case .helperFailed(let failure):
                let command: String
                switch invocation.command {
                case .forge: command = "forge";
                case .scan: command = "scan";
                default: command = "hello"
                }
                output.err(
                    "fpctl: \(command) failed (\(failure.code.rawValue), \(failure.stage?.rawValue ?? "-")): \(failure.message)"
                )
                if invocation.verbose, let detail = failure.detail { output.err(detail) }
                return 1
            default: output.err("fpctl: the font engine could not run (\(engine))")
            }
        } else if error is CommandStopped {
            output.err("fpctl: the font engine stopped without a result")
        } else {
            output.err("fpctl: \(error.localizedDescription)")
        }
        return 3
    }
}

struct CommandStopped: Error {}
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Int32, Never>?
    private var interrupted = false
    func begin() {
        lock.withLock {
            interrupted = false; task = nil
        }
    }
    func install(_ value: Task<Int32, Never>) {
        let cancel = lock.withLock {
            task = value; return interrupted
        }
        if cancel { value.cancel() }
    }
    func cancel() {
        let value = lock.withLock {
            interrupted = true; return task
        }
        value?.cancel()
    }
    func finish() -> Bool {
        lock.withLock {
            task = nil; return interrupted
        }
    }
}
