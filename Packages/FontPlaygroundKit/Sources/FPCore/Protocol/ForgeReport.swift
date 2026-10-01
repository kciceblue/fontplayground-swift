import Foundation

public struct ForgeReport: Codable, Sendable, Equatable {
    public struct MaterialReport: Codable, Sendable, Equatable {
        public var name: String
        public var path: String
        public var index: Int
        public var codepoints: Int
        public var groups: [String]
        public var warnings: [String]

        public init(
            name: String, path: String, index: Int = 0, codepoints: Int,
            groups: [String] = [], warnings: [String] = []
        ) {
            self.name = name
            self.path = path
            self.index = index
            self.codepoints = codepoints
            self.groups = groups
            self.warnings = warnings
        }

        private enum CodingKeys: String, CodingKey {
            case name, path, index, codepoints, groups, warnings
        }
    }

    public struct Issue: Codable, Sendable, Equatable {
        public enum Severity: String, Codable, Sendable {
            case warning, error
        }

        public var code: String
        public var severity: Severity
        public var materialIndex: Int?
        public var group: String?
        public var message: String

        public init(
            code: String, severity: Severity, materialIndex: Int? = nil, group: String? = nil, message: String
        ) {
            self.code = code
            self.severity = severity
            self.materialIndex = materialIndex
            self.group = group
            self.message = message
        }

        private enum CodingKeys: String, CodingKey {
            case code, severity
            case materialIndex = "material_index"
            case group, message
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(code, forKey: .code)
            try values.encode(severity, forKey: .severity)
            try values.encode(materialIndex, forKey: .materialIndex)
            try values.encode(group, forKey: .group)
            try values.encode(message, forKey: .message)
        }
    }

    public struct LicenceNote: Codable, Sendable, Equatable {
        public var licenceClass: String
        public var materialIndexes: [Int]
        public var text: String

        public init(licenceClass: String, materialIndexes: [Int], text: String) {
            self.licenceClass = licenceClass
            self.materialIndexes = materialIndexes
            self.text = text
        }

        private enum CodingKeys: String, CodingKey {
            case licenceClass = "class"
            case materialIndexes = "material_indexes"
            case text
        }
    }

    public var outputPath: String
    public var familyName: String
    public var styleName: String
    public var postscriptName: String
    public var fullName: String
    public var totalCodepoints: Int
    public var totalGlyphs: Int
    public var fsType: Int?
    public var materials: [MaterialReport]
    public var issues: [Issue]
    public var licenceNotes: [LicenceNote]
    public var warnings: [String]
    public var durationSeconds: Double?

    public init(
        outputPath: String, familyName: String = "", styleName: String = "",
        postscriptName: String = "", fullName: String = "", totalCodepoints: Int, totalGlyphs: Int,
        fsType: Int? = nil, materials: [MaterialReport] = [], issues: [Issue] = [],
        licenceNotes: [LicenceNote] = [], warnings: [String] = [], durationSeconds: Double? = nil
    ) {
        self.outputPath = outputPath
        self.familyName = familyName
        self.styleName = styleName
        self.postscriptName = postscriptName
        self.fullName = fullName
        self.totalCodepoints = totalCodepoints
        self.totalGlyphs = totalGlyphs
        self.fsType = fsType
        self.materials = materials
        self.issues = issues
        self.licenceNotes = licenceNotes
        self.warnings = warnings
        self.durationSeconds = durationSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case outputPath = "output_path"
        case familyName = "family_name"
        case styleName = "style_name"
        case postscriptName = "postscript_name"
        case fullName = "full_name"
        case totalCodepoints = "total_codepoints"
        case totalGlyphs = "total_glyphs"
        case fsType = "fs_type"
        case materials, issues
        case licenceNotes = "licence_notes"
        case warnings
        case durationSeconds = "duration_s"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        outputPath = try values.decode(String.self, forKey: .outputPath)
        familyName = try values.decodeIfPresent(String.self, forKey: .familyName) ?? ""
        styleName = try values.decodeIfPresent(String.self, forKey: .styleName) ?? ""
        postscriptName = try values.decodeIfPresent(String.self, forKey: .postscriptName) ?? ""
        fullName = try values.decodeIfPresent(String.self, forKey: .fullName) ?? ""
        totalCodepoints = try values.decode(Int.self, forKey: .totalCodepoints)
        totalGlyphs = try values.decode(Int.self, forKey: .totalGlyphs)
        fsType = try values.decodeIfPresent(Int.self, forKey: .fsType)
        materials = try values.decodeIfPresent([MaterialReport].self, forKey: .materials) ?? []
        issues = try values.decodeIfPresent([Issue].self, forKey: .issues) ?? []
        licenceNotes = try values.decodeIfPresent([LicenceNote].self, forKey: .licenceNotes) ?? []
        warnings = try values.decodeIfPresent([String].self, forKey: .warnings) ?? []
        durationSeconds = try values.decodeIfPresent(Double.self, forKey: .durationSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(outputPath, forKey: .outputPath)
        try values.encode(familyName, forKey: .familyName)
        try values.encode(styleName, forKey: .styleName)
        try values.encode(postscriptName, forKey: .postscriptName)
        try values.encode(fullName, forKey: .fullName)
        try values.encode(totalCodepoints, forKey: .totalCodepoints)
        try values.encode(totalGlyphs, forKey: .totalGlyphs)
        try values.encode(fsType, forKey: .fsType)
        try values.encode(materials, forKey: .materials)
        try values.encode(issues, forKey: .issues)
        try values.encode(licenceNotes, forKey: .licenceNotes)
        try values.encode(warnings, forKey: .warnings)
        try values.encode(durationSeconds, forKey: .durationSeconds)
    }
}
