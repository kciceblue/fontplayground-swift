import Foundation

public struct ForgeSpec: Codable, Sendable, Equatable {
    public struct Expectation: Codable, Sendable, Equatable {
        public var postscriptName: String?
        public var size: Int
        public var mtime: Double

        public init(postscriptName: String? = nil, size: Int, mtime: Double) {
            self.postscriptName = postscriptName
            self.size = size
            self.mtime = mtime
        }

        private enum CodingKeys: String, CodingKey {
            case postscriptName = "postscript_name"
            case size, mtime
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(postscriptName, forKey: .postscriptName)
            try values.encode(size, forKey: .size)
            try values.encode(mtime, forKey: .mtime)
        }
    }

    public struct MaterialSpec: Codable, Sendable, Equatable {
        public var path: String
        public var index: Int
        public var weight: Int?
        public var scale: Double?
        public var expect: Expectation?

        public init(
            path: String, index: Int = 0, weight: Int? = nil, scale: Double? = nil,
            expect: Expectation? = nil
        ) {
            self.path = path
            self.index = index
            self.weight = weight
            self.scale = scale
            self.expect = expect
        }

        private enum CodingKeys: String, CodingKey {
            case path, index, weight, scale, expect
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(path, forKey: .path)
            try values.encode(index, forKey: .index)
            try values.encode(weight, forKey: .weight)
            try values.encode(scale, forKey: .scale)
            try values.encodeIfPresent(expect, forKey: .expect)
        }
    }

    public var materials: [MaterialSpec]
    public var baseIndex: Int
    public var scriptRules: [ScriptGroup: Int]
    public var defaultWeight: Int?
    public var defaultScale: Double
    public var familyName: String
    public var styleName: String

    public init(
        materials: [MaterialSpec] = [], baseIndex: Int = 0, scriptRules: [ScriptGroup: Int] = [:],
        defaultWeight: Int? = nil, defaultScale: Double = 1.0,
        familyName: String = "Forged", styleName: String = "Regular"
    ) {
        self.materials = materials
        self.baseIndex = baseIndex
        self.scriptRules = scriptRules
        self.defaultWeight = defaultWeight
        self.defaultScale = defaultScale
        self.familyName = familyName
        self.styleName = styleName
    }

    public func resolvedWeight(_ i: Int) -> Int? {
        materials[i].weight ?? defaultWeight
    }

    public func resolvedScale(_ i: Int) -> Double {
        materials[i].scale ?? defaultScale
    }

    private enum CodingKeys: String, CodingKey {
        case materials
        case baseIndex = "base_index"
        case scriptRules = "script_rules"
        case defaultWeight = "default_weight"
        case defaultScale = "default_scale"
        case familyName = "family_name"
        case styleName = "style_name"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        materials = try values.decode([MaterialSpec].self, forKey: .materials)
        baseIndex = try values.decodeIfPresent(Int.self, forKey: .baseIndex) ?? 0
        let rules = try values.decodeIfPresent([String: Int?].self, forKey: .scriptRules) ?? [:]
        scriptRules = Dictionary(
            uniqueKeysWithValues: rules.compactMap { key, value in
                guard let group = ScriptGroup(rawValue: key), let index = value else { return nil }
                return (group, index)
            }
        )
        defaultWeight = try values.decodeIfPresent(Int.self, forKey: .defaultWeight)
        defaultScale = try values.decodeIfPresent(Double.self, forKey: .defaultScale) ?? 1.0
        familyName = try values.decodeIfPresent(String.self, forKey: .familyName) ?? "Forged"
        styleName = try values.decodeIfPresent(String.self, forKey: .styleName) ?? "Regular"
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(materials, forKey: .materials)
        try values.encode(baseIndex, forKey: .baseIndex)
        // Explicit nulls distinguish the complete v1 rule table from an omitted field.
        let rules = Dictionary(uniqueKeysWithValues: ScriptGroup.allCases.map { ($0.rawValue, scriptRules[$0]) })
        try values.encode(rules, forKey: .scriptRules)
        try values.encode(defaultWeight, forKey: .defaultWeight)
        try values.encode(defaultScale, forKey: .defaultScale)
        try values.encode(familyName, forKey: .familyName)
        try values.encode(styleName, forKey: .styleName)
    }
}
