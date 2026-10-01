import Foundation

public enum RecipeDocumentError: Error, Equatable {
    case unreadable, notARecipe, newerVersion(Int), malformed(field: String)
}

public struct RecipeDocument: Codable, Sendable, Equatable {
    public static let format = "fontrecipe"
    public static let currentVersion = 1
    public static let fileExtension = "fontrecipe"
    public static let typeIdentifier = "io.github.kciceblue.fontplayground.recipe"
    public static let autosaveFileName = "last.fontrecipe"
    public struct DocumentMaterial: Codable, Sendable, Equatable {
        public var face: PortableFaceIdentity
        public var weight: Int?
        public var scale: Double?
        public init(face: PortableFaceIdentity, weight: Int? = nil, scale: Double? = nil) {
            self.face = face; self.weight = weight; self.scale = scale
        }
    }
    public struct Defaults: Codable, Sendable, Equatable {
        public var weight: Int?
        public var scale: Double
        public init(weight: Int? = nil, scale: Double = 1) { self.weight = weight; self.scale = scale }
    }
    public struct Names: Codable, Sendable, Equatable {
        public var family: String
        public var style: String
        public var familyEdited: Bool
        public var styleEdited: Bool
        public init(
            family: String = "Forged", style: String = "Regular", familyEdited: Bool = false, styleEdited: Bool = false
        ) {
            self.family = family; self.style = style; self.familyEdited = familyEdited; self.styleEdited = styleEdited
        }
        private enum CodingKeys: String, CodingKey {
            case family, style, familyEdited = "family_edited", styleEdited = "style_edited"
        }
    }
    public var materials: [DocumentMaterial]
    public var main: Int
    public var rules: [ScriptGroup: Int]
    public var defaults: Defaults
    public var names: Names
    public var sampleText: String
    private var unknownRules: [String: Int] = [:]

    public init(recipe: Recipe) {
        materials = recipe.materials.map {
            DocumentMaterial(face: $0.face.identity, weight: $0.weight, scale: $0.scale)
        }
        main = recipe.baseIndex ?? 0
        rules = recipe.pins.compactMapValues { recipe.index(of: $0) }
        defaults = Defaults(weight: recipe.defaultWeight, scale: recipe.defaultScale)
        names = Names(
            family: recipe.names.family, style: recipe.names.style,
            familyEdited: recipe.names.familyEdited, styleEdited: recipe.names.styleEdited)
        sampleText = recipe.sampleText
    }

    public static func decode(_ data: Data) throws -> RecipeDocument {
        do { return try JSONDecoder().decode(Self.self, from: data) } catch let error as RecipeDocumentError {
            throw error
        } catch { throw RecipeDocumentError.unreadable }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard let object = value.object, object["format"] == .string(Self.format),
            case .integer(let version) = object["version"], version >= 1
        else { throw RecipeDocumentError.notARecipe }
        guard version <= Self.currentVersion else { throw RecipeDocumentError.newerVersion(version) }
        self.init(recipe: Recipe())
        let materialValues: [JSONValue]
        if let value = object["materials"] {
            guard let array = value.array else { throw RecipeDocumentError.malformed(field: "materials") }
            materialValues = array
        } else {
            materialValues = []
        }
        materials = try materialValues.enumerated().map { index, value in
            let path = "materials[\(index)]"
            let row = try Self.object(value, field: path)
            let face = try Self.object(row["face"], field: path + ".face")
            let identity = PortableFaceIdentity(
                postscriptName: try Self.optionalString(face["postscript_name"], field: path + ".face.postscript_name"),
                family: try Self.string(face["family"], field: path + ".face.family"),
                style: try Self.string(face["style"], field: path + ".face.style"),
                path: try Self.string(face["path"], field: path + ".face.path"),
                index: try Self.integer(face["index"], field: path + ".face.index"))
            return DocumentMaterial(
                face: identity, weight: try Self.optionalInt(row["weight"], field: path + ".weight"),
                scale: try Self.optionalNumber(row["scale"], field: path + ".scale"))
        }
        if let value = object["main"] { main = try Self.integer(value, field: "main") }
        if let value = object["rules"] {
            for (name, value) in try Self.object(value, field: "rules").sorted(by: { $0.key < $1.key }) {
                let index = try Self.integer(value, field: "rules.\(name)")
                if let group = ScriptGroup(rawValue: name) { rules[group] = index } else { unknownRules[name] = index }
            }
        }
        if let value = object["defaults"] {
            let values = try Self.object(value, field: "defaults")
            defaults.weight = try Self.optionalInt(values["weight"], field: "defaults.weight")
            if let scale = values["scale"] { defaults.scale = try Self.number(scale, field: "defaults.scale") }
        }
        if let value = object["names"] {
            let values = try Self.object(value, field: "names")
            if let value = values["family"] { names.family = try Self.string(value, field: "names.family") }
            if let value = values["style"] { names.style = try Self.string(value, field: "names.style") }
            if let value = values["family_edited"] {
                names.familyEdited = try Self.bool(value, field: "names.family_edited")
            }
            if let value = values["style_edited"] {
                names.styleEdited = try Self.bool(value, field: "names.style_edited")
            }
        }
        if let value = object["sample_text"] { sampleText = try Self.string(value, field: "sample_text") }
    }

    public func encode(to encoder: Encoder) throws {
        // Explicit nulls belong to the file contract even though synthesized Optional encoding omits them.
        let rows: [JSONValue] = materials.map { material in
            .object([
                "face": .object([
                    "postscript_name": material.face.postscriptName.map(JSONValue.string) ?? .null,
                    "family": .string(material.face.family), "style": .string(material.face.style),
                    "path": .string(material.face.path), "index": .integer(material.face.index),
                ]),
                "weight": material.weight.map(JSONValue.integer) ?? .null,
                "scale": material.scale.map(JSONValue.number) ?? .null,
            ])
        }
        var rawRules = unknownRules.mapValues(JSONValue.integer)
        for (group, index) in rules { rawRules[group.rawValue] = .integer(index) }
        try JSONValue.object([
            "format": .string(Self.format), "version": .integer(Self.currentVersion), "materials": .array(rows),
            "main": .integer(main), "rules": .object(rawRules),
            "defaults": .object([
                "weight": defaults.weight.map(JSONValue.integer) ?? .null, "scale": .number(defaults.scale),
            ]),
            "names": .object([
                "family": .string(names.family), "style": .string(names.style),
                "family_edited": .bool(names.familyEdited), "style_edited": .bool(names.styleEdited),
            ]),
            "sample_text": .string(sampleText),
        ]).encode(to: encoder)
    }

    public func makeRecipe(catalog: FaceCatalog) -> (recipe: Recipe, report: LoadReport) {
        var loader = RecipeLoader()
        for (position, material) in materials.enumerated() {
            let resolution = catalog.resolve(material.face)
            let outcome: LoadReport.Outcome?
            switch resolution {
            case .byPath: outcome = .byPath
            case .byPostScriptName: outcome = .byPostScriptName
            case .byFamilyAndStyle: outcome = .byFamilyAndStyle
            case .unresolved: outcome = nil
            }
            loader.append(
                identity: material.face, face: resolution.face, outcome: outcome,
                weight: material.weight, scale: material.scale, position: position, catalog: catalog)
        }
        var rawRules = unknownRules.mapValues(JSONValue.integer)
        for (group, index) in rules { rawRules[group.rawValue] = .integer(index) }
        let base = loader.base(main), pins = loader.rules(rawRules, tolerant: false)
        return (
            .restoring(
                materials: loader.materials, baseKey: base, pins: pins, defaultWeight: defaults.weight,
                defaultScale: defaults.scale,
                names: RecipeNames(
                    family: names.family, style: names.style,
                    familyEdited: names.familyEdited, styleEdited: names.styleEdited), sampleText: sampleText),
            loader.report
        )
    }

    private static func object(_ value: JSONValue?, field: String) throws -> [String: JSONValue] {
        guard let object = value?.object else { throw RecipeDocumentError.malformed(field: field) }; return object
    }
    private static func string(_ value: JSONValue?, field: String) throws -> String {
        guard case .string(let value) = value else { throw RecipeDocumentError.malformed(field: field) }; return value
    }
    private static func integer(_ value: JSONValue?, field: String) throws -> Int {
        guard case .integer(let value) = value else { throw RecipeDocumentError.malformed(field: field) }; return value
    }
    private static func number(_ value: JSONValue, field: String) throws -> Double {
        switch value {
        case .integer(let value): return Double(value)
        case .number(let value) where value.isFinite: return value
        default: throw RecipeDocumentError.malformed(field: field)
        }
    }
    private static func bool(_ value: JSONValue, field: String) throws -> Bool {
        guard case .bool(let value) = value else { throw RecipeDocumentError.malformed(field: field) }; return value
    }
    private static func optionalString(_ value: JSONValue?, field: String) throws -> String? {
        guard let value, value != .null else { return nil }; return try string(value, field: field)
    }
    private static func optionalInt(_ value: JSONValue?, field: String) throws -> Int? {
        guard let value, value != .null else { return nil }; return try integer(value, field: field)
    }
    private static func optionalNumber(_ value: JSONValue?, field: String) throws -> Double? {
        guard let value, value != .null else { return nil }; return try number(value, field: field)
    }
}
