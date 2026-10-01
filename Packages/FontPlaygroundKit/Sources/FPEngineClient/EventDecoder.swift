import FPCore
import Foundation

enum DecodedEvent: Sendable, Equatable {
    case hello(EngineHello)
    case progress(EngineProgress)
    case face(FaceRecord)
    case fileError(ScanFileError)
    case result(command: String, summary: ScanSummary?, report: ForgeReport?)
    case error(HelperFailure)
}

struct EventDecoder {
    private struct Envelope: Decodable {
        var protocolVersion: Int
        var type: String
        enum CodingKeys: String, CodingKey { case protocolVersion = "protocol", type }
    }
    private struct Face: Decodable {
        var face: FaceRecord
        enum CodingKeys: String, CodingKey { case face }
    }
    private struct Result: Decodable {
        var command: String
        var summary: ScanSummary?
        var report: ForgeReport?
        enum CodingKeys: String, CodingKey { case command, summary, report }
    }

    func decode(_ line: Data, command: String) throws -> DecodedEvent? {
        let decoder = JSONDecoder()
        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: line) } catch {
            throw EngineError.protocolViolation(
                "not a JSON event: \(String(decoding: line.prefix(200), as: UTF8.self))", stderrTail: ""
            )
        }
        guard envelope.protocolVersion == EngineClient.supportedProtocol else {
            throw EngineError.incompatibleHelper(
                reported: envelope.protocolVersion, supported: EngineClient.supportedProtocol)
        }
        let known = ["hello", "progress", "face", "file_error", "result", "error"]
        guard known.contains(envelope.type) else { return nil }
        let allowed =
            command == "hello"
            ? ["hello", "result", "error"]
            : command == "scan"
                ? ["progress", "face", "file_error", "result", "error"] : ["progress", "result", "error"]
        guard allowed.contains(envelope.type) else {
            throw EngineError.protocolViolation("unexpected \(envelope.type) during \(command)", stderrTail: "")
        }
        do {
            switch envelope.type {
            case "hello": return .hello(try decoder.decode(EngineHello.self, from: line))
            case "progress": return .progress(try decoder.decode(EngineProgress.self, from: line))
            case "face": return .face(try decoder.decode(Face.self, from: line).face)
            case "file_error": return .fileError(try decoder.decode(ScanFileError.self, from: line))
            case "error": return .error(try decoder.decode(HelperFailure.self, from: line))
            default:
                let result = try decoder.decode(Result.self, from: line)
                guard result.command == command else {
                    throw EngineError.protocolViolation(
                        "result command \(result.command) does not match \(command)", stderrTail: "")
                }
                guard command != "scan" || result.summary != nil, command != "forge" || result.report != nil else {
                    throw EngineError.protocolViolation("result lacks \(command) payload", stderrTail: "")
                }
                return .result(command: result.command, summary: result.summary, report: result.report)
            }
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.protocolViolation("cannot decode \(envelope.type): \(error)", stderrTail: "")
        }
    }
}
