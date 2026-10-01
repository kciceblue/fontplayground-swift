import Foundation

struct SelfTestSummary: Codable, Equatable, Sendable {
    var result: String
    var failedSteps: [String]
    var durationMs: Int
    var appVersion: String
    var build: String
    var engine: String
    var fpengineVersion: String
    var macos: String
    enum CodingKeys: String, CodingKey {
        case result, build, engine, macos
        case failedSteps = "failed_steps", durationMs = "duration_ms", appVersion = "app_version"
        case fpengineVersion = "fpengine_version"
    }
}

/// Explicit field order makes the headless contract stable across Foundation versions.
struct SelfTestOutput: Sendable {
    let output: @Sendable (String) -> Void
    func step(_ step: SelfTestStep, ok: Bool, milliseconds: Int, detail: [String: String], error: String?) {
        output(
            Self.line([
                ("type", "step"), ("step", step.rawValue), ("ok", ok), ("duration_ms", milliseconds),
                ("detail", detail), ("error", error as Any? ?? NSNull()),
            ]))
        let message =
            ok ? "ok (\(String(format: "%.1f", Double(milliseconds) / 1000)) s)" : "FAILED: \(error ?? "unknown error")"
        Self.error("self-test: \(step.rawValue) \(message)")
    }
    func summary(_ value: SelfTestSummary) {
        output(
            Self.line([
                ("type", "summary"), ("result", value.result), ("failed_steps", value.failedSteps),
                ("duration_ms", value.durationMs), ("app_version", value.appVersion), ("build", value.build),
                ("engine", value.engine), ("fpengine_version", value.fpengineVersion), ("macos", value.macos),
            ]))
    }
    private static func line(_ fields: [(String, Any)]) -> String {
        "{"
            + fields.map { key, value in
                let data = try! JSONSerialization.data(
                    withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
                return "\"\(key)\":" + String(decoding: data, as: UTF8.self)
            }.joined(separator: ",") + "}"
    }
    static func error(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

func selfTestMilliseconds(_ duration: Duration) -> Int {
    let components = duration.components
    return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
}
