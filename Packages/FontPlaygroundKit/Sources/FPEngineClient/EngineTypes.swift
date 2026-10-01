import Foundation

public enum EngineStage: String, Sendable, Codable, CaseIterable {
    case validate, plan, prepare, merge, finish, verify, done, scan
}

public struct EngineProgress: Sendable, Equatable, Codable {
    public var stage: EngineStage
    public var fraction: Double
    public var materialIndex: Int?
    public var done: Int?
    public var total: Int?

    public init(stage: EngineStage, fraction: Double, materialIndex: Int? = nil, done: Int? = nil, total: Int? = nil) {
        self.stage = stage
        self.fraction = fraction
        self.materialIndex = materialIndex
        self.done = done
        self.total = total
    }

    private enum CodingKeys: String, CodingKey {
        case stage, fraction, materialIndex = "material_index", done, total
    }
}

public struct EngineHello: Sendable, Equatable, Codable {
    public var protocolVersion: Int
    public var fpengineVersion: String
    public var python: String
    public var fonttools: String
    public var unicodeVersion: String
    public var platform: String
    public var capabilities: [String]
    public var faceReaderVersion: Int

    public init(
        protocolVersion: Int = 1, fpengineVersion: String, python: String, fonttools: String,
        unicodeVersion: String = "", platform: String, capabilities: [String], faceReaderVersion: Int = 0
    ) {
        self.protocolVersion = protocolVersion
        self.fpengineVersion = fpengineVersion
        self.python = python
        self.fonttools = fonttools
        self.unicodeVersion = unicodeVersion
        self.platform = platform
        self.capabilities = capabilities
        self.faceReaderVersion = faceReaderVersion
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol", fpengineVersion = "fpengine_version", python, fonttools
        case unicodeVersion = "unicode_version", platform, capabilities, faceReaderVersion = "face_reader_version"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
        fpengineVersion = try values.decode(String.self, forKey: .fpengineVersion)
        python = try values.decode(String.self, forKey: .python)
        fonttools = try values.decode(String.self, forKey: .fonttools)
        unicodeVersion = try values.decodeIfPresent(String.self, forKey: .unicodeVersion) ?? ""
        platform = try values.decode(String.self, forKey: .platform)
        capabilities = try values.decode([String].self, forKey: .capabilities)
        faceReaderVersion = try values.decodeIfPresent(Int.self, forKey: .faceReaderVersion) ?? 0
    }
}

public enum FileErrorCode: String, Sendable, Codable {
    case notFound = "not_found", ioError = "io_error", unreadable, `internal`
}

public struct ScanFileError: Sendable, Equatable, Codable {
    public var path: String
    public var code: FileErrorCode
    public var message: String
    public init(path: String, code: FileErrorCode, message: String) {
        self.path = path
        self.code = code
        self.message = message
    }
    private enum CodingKeys: String, CodingKey { case path, code, message }
}

public struct ScanSummary: Sendable, Equatable, Codable {
    public var files: Int
    public var faces: Int
    public var fileErrors: Int
    public var duplicates: Int
    public init(files: Int, faces: Int, fileErrors: Int, duplicates: Int) {
        self.files = files
        self.faces = faces
        self.fileErrors = fileErrors
        self.duplicates = duplicates
    }
    private enum CodingKeys: String, CodingKey { case files, faces, fileErrors = "file_errors", duplicates }
}

public enum HelperErrorCode: String, Sendable, Codable, CaseIterable {
    case badRequest = "bad_request", validate, staleMaterial = "stale_material", unsupportedFont = "unsupported_font"
    case aatUnsupportedScript = "aat_unsupported_script", glyphLimit = "glyph_limit", prepareFailed = "prepare_failed"
    case mergeFailed = "merge_failed", finishFailed = "finish_failed", verifyFailed = "verify_failed"
    case ioError = "io_error", `internal`
}

public struct HelperFailure: Sendable, Equatable, Codable {
    public var code: HelperErrorCode
    public var stage: EngineStage?
    public var materialIndex: Int?
    public var message: String
    public var detail: String?
    public init(
        code: HelperErrorCode, stage: EngineStage? = nil, materialIndex: Int? = nil, message: String,
        detail: String? = nil
    ) {
        self.code = code
        self.stage = stage
        self.materialIndex = materialIndex
        self.message = message
        self.detail = detail
    }
    private enum CodingKeys: String, CodingKey { case code, stage, materialIndex = "material_index", message, detail }
}

public enum EngineProcessEvent: Sendable, Equatable {
    case launched(pid: Int32, command: String)
    case exited(pid: Int32, exitCode: Int32?, signal: Int32?)
}
