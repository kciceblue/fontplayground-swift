import Foundation

public struct EngineLaunch: Sendable, Equatable {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]
    public enum Source: Sendable, Equatable { case bundled, environment, explicit }
    public var source: Source
    public static let bundledHelperCandidates = [
        "Contents/Helpers/fpengine/bin/python3", "Contents/Resources/fpengine/bin/python3",
    ]

    public init(
        executableURL: URL, arguments: [String] = ["-I", "-B", "-m", "fpengine"],
        environment: [String: String] = [:], source: Source = .explicit
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.source = source
    }

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment, bundleURL: URL? = Bundle.main.bundleURL,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) throws -> EngineLaunch {
        var searched: [String] = []
        if let bundleURL {
            for candidate in bundledHelperCandidates {
                let url = bundleURL.appendingPathComponent(candidate)
                searched.append(url.path)
                if isExecutable(url.path) { return .init(executableURL: url, source: .bundled) }
            }
        }
        if let path = environment["FP_ENGINE_PYTHON"], !path.isEmpty {
            searched.append(path)
            if isExecutable(path) { return .init(executableURL: URL(fileURLWithPath: path), source: .environment) }
        }
        throw EngineError.helperNotFound(searched: searched)
    }
}

public struct EngineTimeouts: Sendable, Equatable {
    public var hello: Duration
    public var scanIdle: Duration
    public var forge: Duration
    public var terminationGrace: Duration
    public init(
        hello: Duration = .seconds(30), scanIdle: Duration = .seconds(120), forge: Duration = .seconds(900),
        terminationGrace: Duration = .seconds(2)
    ) {
        self.hello = hello
        self.scanIdle = scanIdle
        self.forge = forge
        self.terminationGrace = terminationGrace
    }
}

public struct EngineConfiguration: Sendable {
    public var launch: EngineLaunch
    public var temporaryDirectory: URL?
    public var timeouts: EngineTimeouts
    public var stderrCapacity: Int
    public var logHandler: (@Sendable (String) -> Void)?
    /// Read-only lifecycle diagnostics; observers must not call back into or wait on a client run.
    public var processObserver: (@Sendable (EngineProcessEvent) -> Void)?
    public init(
        launch: EngineLaunch, temporaryDirectory: URL? = nil, timeouts: EngineTimeouts = .init(),
        stderrCapacity: Int = 65_536, logHandler: (@Sendable (String) -> Void)? = nil,
        processObserver: (@Sendable (EngineProcessEvent) -> Void)? = nil
    ) {
        self.launch = launch
        self.temporaryDirectory = temporaryDirectory
        self.timeouts = timeouts
        self.stderrCapacity = stderrCapacity
        self.logHandler = logHandler
        self.processObserver = processObserver
    }
}
