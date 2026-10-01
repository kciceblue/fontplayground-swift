import Foundation

public struct LegacyRecipeReport: Sendable, Equatable {
    public var readable: Bool
    public var load: LoadReport
    public var lastSaveDirectory: String?
    public var ignoredOutputPath: String?
    public init(
        readable: Bool = true, load: LoadReport = .init(), lastSaveDirectory: String? = nil,
        ignoredOutputPath: String? = nil
    ) {
        self.readable = readable; self.load = load; self.lastSaveDirectory = lastSaveDirectory;
        self.ignoredOutputPath = ignoredOutputPath
    }
}

public struct LegacySettingsReport: Sendable, Equatable {
    public struct DroppedFolder: Sendable, Equatable {
        public let path: String
        public let reason: FolderCheck.Failure
        public init(path: String, reason: FolderCheck.Failure) { self.path = path; self.reason = reason }
    }
    public var readable = true
    public var droppedFolders: [DroppedFolder] = []
    public var ignoredKeys: [String] = []
    public init() {}
}

public enum LegacyImport {
    public static let folderName = "FontPlayground"
    public static let recipeFileName = "forge_last.json"
    public static let settingsFileName = "settings.json"
    public static func legacyFolder(home: String) -> String {
        URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/\(folderName)").path
    }

    public static func recipe(fromForgeLast data: Data, catalog: FaceCatalog, probe: any FileSystemProbe) -> (
        recipe: Recipe, report: LegacyRecipeReport
    ) {
        guard let object = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object else {
            return (Recipe(), LegacyRecipeReport(readable: false))
        }
        var loader = RecipeLoader()
        let rows: [JSONValue]
        switch object["materials"] {
        case nil, .null?: rows = []
        case .array(let values)?: rows = values
        default:
            // A damaged or hand-edited file: report it rather than importing an empty recipe as if it were complete.
            rows = []
            loader.report.outcomes.append(.malformed)
        }
        for (position, value) in rows.enumerated() {
            guard let row = value.object,
                let key = JSONValue.array([row["path"] ?? .null, row["index"] ?? .null]).asKey
            else {
                loader.report.outcomes.append(.malformed)
                continue
            }
            let name = basename(key.path)
            let windowsName = WindowsFonts.faceName(forFile: name, index: key.index)
            let identity = PortableFaceIdentity(
                postscriptName: nil,
                family: windowsName?.family ?? (name as NSString).deletingPathExtension,
                style: windowsName?.style ?? "Regular", path: key.path, index: key.index)
            var face = catalog.face(for: key)
            var outcome: LoadReport.Outcome = .byPath
            if face == nil && FolderCheck.looksWindows(key.path), let windowsName {
                face = catalog.face(family: windowsName.family, style: windowsName.style)
                outcome = .byWindowsFileName
            }
            if face == nil {
                face = catalog.faces.first {
                    $0.index == key.index && basename($0.path).lowercased() == name.lowercased()
                }
                outcome = .byFileName
            }
            loader.append(
                identity: identity, face: face, outcome: face == nil ? nil : outcome,
                weight: row["weight"]?.asInt, scale: row["scale"]?.asFloat, position: position, catalog: catalog)
        }
        let base = loader.base(object["base_index"]?.asInt ?? 0)
        var pins: [ScriptGroup: FaceKey] = [:]
        if let storedPins = object["pins"] {
            for (name, value) in (storedPins.object ?? [:]).sorted(by: { $0.key < $1.key }) {
                if value == .null { continue }
                if let group = ScriptGroup(rawValue: name), let key = value.asKey,
                    let index = loader.originalKeys[key]
                {
                    pins[group] = loader.materials[index].key
                } else {
                    loader.report.ignoredRules.append("\(name)=\(value.description)")
                }
            }
        } else {
            pins = loader.rules(object["script_rules"]?.object ?? [:], tolerant: true)
        }
        let faces = loader.materials.map(\.face)
        let autoFamily = Naming.defaultFamilyName(faces), autoStyle = Naming.defaultStyle(faces.first)
        let family = object["family_name"]?.string, style = object["style_name"]?.string
        let flags = object["names_edited"]?.object
        let familyEdited = flags.map { $0["family"]?.truthy ?? false } ?? (family != nil && family != autoFamily)
        let styleEdited = flags.map { $0["style"]?.truthy ?? false } ?? (style != nil && style != autoStyle)
        let recipe = Recipe.restoring(
            materials: loader.materials, baseKey: base, pins: pins,
            defaultWeight: object["default_weight"]?.asInt, defaultScale: object["default_scale"]?.asFloat ?? 1,
            names: RecipeNames(
                family: familyEdited ? (family ?? autoFamily) : autoFamily,
                style: styleEdited ? (style ?? autoStyle) : autoStyle,
                familyEdited: familyEdited, styleEdited: styleEdited),
            sampleText: object["sample_text"]?.string ?? Samples.defaultSample)
        var report = LegacyRecipeReport(load: loader.report)
        if flags?["output"]?.truthy == true, let output = object["output_path"]?.string {
            let parent =
                output.lastIndex(where: { $0 == "/" || $0 == "\\" }).map { index in
                    index == output.startIndex ? String(output[...index]) : String(output[..<index])
                } ?? output
            switch FolderCheck.check(parent, using: probe) {
            case .success(let accepted): report.lastSaveDirectory = accepted.path
            case .failure: report.ignoredOutputPath = output
            }
        }
        return (recipe, report)
    }

    public static func settings(from data: Data, probe: any FileSystemProbe) -> (
        settings: AppSettings, report: LegacySettingsReport
    ) {
        var result = AppSettings(), report = LegacySettingsReport()
        guard let object = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object else {
            report.readable = false
            return (result, report)
        }
        if let value = object["theme"] {
            if let string = value.string, let appearance = AppSettings.Appearance(rawValue: string) {
                result.appearance = appearance
            } else {
                report.ignoredKeys.append("theme")
            }
        }
        if let value = object["preview_size"] {
            if case .integer(let size) = value, AppSettings.previewPointSizes.contains(size) {
                result.previewPointSize = size
            } else {
                report.ignoredKeys.append("preview_size")
            }
        }
        if let value = object["colour_by_font"] {
            if case .bool(let flag) = value {
                result.colourByFont = flag
            } else {
                report.ignoredKeys.append("colour_by_font")
            }
        }
        if let value = object["extra_dirs"] {
            if let folders = value.array {
                var seen = Set<String>()
                for (index, value) in folders.enumerated() {
                    guard let folder = value.string else { report.ignoredKeys.append("extra_dirs[\(index)]"); continue }
                    switch FolderCheck.check(folder, using: probe) {
                    case .success(let accepted):
                        if seen.insert(accepted.path).inserted { result.extraFolders.append(accepted.path) }
                    case .failure(let reason): report.droppedFolders.append(.init(path: folder, reason: reason))
                    }
                }
            } else {
                report.ignoredKeys.append("extra_dirs")
            }
        }
        report.ignoredKeys.sort()
        return (result, report)
    }

    private static func basename(_ path: String) -> String {
        guard let separator = path.lastIndex(where: { $0 == "/" || $0 == "\\" }) else { return path }
        return String(path[path.index(after: separator)...])
    }
}
