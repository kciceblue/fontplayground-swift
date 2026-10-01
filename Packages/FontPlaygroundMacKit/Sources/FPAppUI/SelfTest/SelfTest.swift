import CoreText
import Darwin
import FPCore
import FPEngineClient
import Foundation

public enum SelfTest {
    public static func run(arguments: [String], environment: [String: String]) async -> Int32 {
        let options: SelfTestOptions
        do { options = try SelfTestOptions.parse(arguments) } catch {
            SelfTestOutput.error("self-test: \(error)")
            return 2
        }
        let lines = SelfTestLines()
        let runner = SelfTestRunner(options: options, dependencies: live(environment: environment)) { line in
            lines.append(line)
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }
        let result = await runner.run()
        if let report = options.reportURL {
            do {
                var directory: ObjCBool = false
                guard
                    FileManager.default.fileExists(
                        atPath: report.deletingLastPathComponent().path, isDirectory: &directory),
                    directory.boolValue
                else { throw SelfTestFailure("report parent folder does not exist") }
                try AtomicFile.write(Data(lines.text.utf8), to: report.path)
            } catch { SelfTestOutput.error("self-test: couldn't write report: \(error)") }
        }
        return result.exitCode
    }

    private static func live(environment: [String: String]) -> SelfTestDependencies {
        var injected: String?
        #if DEBUG
            injected = environment["FP_SELF_TEST_INJECT_FAILURE"]
        #endif
        return SelfTestDependencies(
            bundleInfo: {
                BundleInfo(
                    identifier: Bundle.main.bundleIdentifier,
                    shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                        ?? "",
                    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
            },
            engine: { temporary in
                let launch = try EngineLaunch.resolve(environment: environment)
                return (
                    EngineClient(configuration: .init(launch: launch, temporaryDirectory: temporary)),
                    launch.source == .bundled ? .embedded : .dev
                )
            },
            availableFontURLs: { CTFontManagerCopyAvailableFontURLs() as? [URL] ?? [] },
            checkBuiltFont: BuiltFontCheck.read,
            recipeData: {
                guard let url = Bundle.module.url(forResource: "self-test", withExtension: "fontrecipe") else {
                    throw SelfTestFailure("bundled self-test recipe is missing")
                }
                return try Data(contentsOf: url)
            },
            temporaryRoot: { FileManager.default.temporaryDirectory.appendingPathComponent("fp-self-test-\(UUID())") },
            helperProcessIDs: childProcessIDs, injectedFailure: injected)
    }

    private static func childProcessIDs() -> Set<Int32> {
        let estimated = max(Int(proc_listchildpids(getpid(), nil, 0)), 64)
        var children = [Int32](repeating: 0, count: estimated + 64)
        let capacity = Int32(children.count * MemoryLayout<Int32>.size)
        _ = children.withUnsafeMutableBytes { proc_listchildpids(getpid(), $0.baseAddress, capacity) }
        return Set(
            children.filter { pid in
                guard pid > 0 else { return false }
                var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                return proc_pidpath(pid, &path, UInt32(path.count)) > 0
            })
    }
}

private final class SelfTestLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var text: String { lock.withLock { lines.joined(separator: "\n") + "\n" } }
}

struct SelfTestOptions: Equatable, Sendable {
    var reportURL: URL?
    var keepTemporaryFiles = false
    var requireEmbeddedEngine = false
    var timeout: Duration = .seconds(180)
    static func parse(_ arguments: [String]) throws -> SelfTestOptions {
        var options = SelfTestOptions(), index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--self-test": break
            case "--self-test-keep": options.keepTemporaryFiles = true
            case "--require-embedded-engine": options.requireEmbeddedEngine = true
            case "--self-test-report", "--self-test-timeout":
                index += 1
                guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                    throw SelfTestUsageError(message: "missing value for \(argument)")
                }
                if argument == "--self-test-report" {
                    guard !arguments[index].isEmpty else { throw SelfTestUsageError(message: "empty report path") }
                    options.reportURL = URL(fileURLWithPath: arguments[index]).standardizedFileURL
                } else {
                    guard let seconds = Int(arguments[index]), (10...3600).contains(seconds) else {
                        throw SelfTestUsageError(message: "--self-test-timeout must be an integer from 10 to 3600")
                    }
                    options.timeout = .seconds(seconds)
                }
            default:
                if argument.hasPrefix("--self-test") {
                    throw SelfTestUsageError(message: "unknown argument \(argument)")
                }
            }
            index += 1
        }
        return options
    }
}

struct SelfTestUsageError: Error, CustomStringConvertible {
    var message: String
    var description: String { message }
}

struct SelfTestFailure: Error, CustomStringConvertible {
    var description: String
    var detail: [String: String] = [:]
    var exitCode: Int32 = 1
    init(_ message: String, detail: [String: String] = [:], exitCode: Int32 = 1) {
        description = message; self.detail = detail; self.exitCode = exitCode
    }
}

enum SelfTestStep: String, CaseIterable, Sendable {
    case environment, engine, recipe, discover, scan, forge, verify, cancel, cleanup
    var budget: Int {
        switch self {
        case .environment, .recipe: 1
        case .engine: 20
        case .discover, .cancel: 10
        case .scan: 30
        case .forge: 120
        case .verify, .cleanup: 5
        }
    }
}
enum EngineKind: String, Sendable { case embedded, dev }
struct BundleInfo: Sendable, Equatable {
    var identifier: String?
    var shortVersion: String
    var build: String
}
struct SelfTestDependencies: Sendable {
    var bundleInfo: @Sendable () -> BundleInfo
    var engine: @Sendable (URL) throws -> (any EngineRunning, EngineKind)
    var availableFontURLs: @Sendable () -> [URL]
    var checkBuiltFont: @Sendable (URL, String, String) throws -> BuiltFontCheck
    var recipeData: @Sendable () throws -> Data
    var temporaryRoot: @Sendable () throws -> URL
    var helperProcessIDs: @Sendable () -> Set<Int32>
    var removeTemporaryRoot: @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    var injectedFailure: String?
}
