import Foundation

public struct Recipe: Sendable, Equatable, Codable {
    public private(set) var materials: [Material] = []
    public private(set) var baseKey: FaceKey?
    public private(set) var pins: [ScriptGroup: FaceKey] = [:]
    public private(set) var defaultWeight: Int?
    public private(set) var defaultScale: Double = 1
    public private(set) var names = RecipeNames()
    public private(set) var sampleText = Samples.defaultSample

    public init() {}

    // Persistence restores rows as a batch: replaying reorder operations would clear saved main adjustments.
    static func restoring(
        materials: [Material], baseKey: FaceKey?, pins: [ScriptGroup: FaceKey],
        defaultWeight: Int?, defaultScale: Double, names: RecipeNames, sampleText: String
    ) -> Recipe {
        var recipe = Recipe()
        recipe.materials = materials; recipe.baseKey = baseKey; recipe.pins = pins
        recipe.defaultWeight = defaultWeight; recipe.defaultScale = defaultScale; recipe.names = names
        recipe.sampleText =
            sampleText.isEmpty || sampleText == Samples.oldDefaultSample ? Samples.defaultSample : sampleText
        recipe.refreshNames()
        return recipe
    }

    public var main: FaceRecord? { materials.first?.face }
    public var base: FaceRecord? { baseIndex.map { materials[$0].face } }
    public var baseIndex: Int? { materials.isEmpty ? nil : (baseKey.flatMap(index(of:)) ?? 0) }
    public var keys: [FaceKey] { materials.map(\.key) }
    public func contains(_ key: FaceKey) -> Bool { index(of: key) != nil }
    public func material(for key: FaceKey) -> Material? { index(of: key).map { materials[$0] } }
    public func index(of key: FaceKey) -> Int? { materials.firstIndex { $0.key == key } }
    public var suggestedFileName: String { Naming.fileName(family: names.family, style: names.style) }

    @discardableResult public mutating func add(_ face: FaceRecord, for language: LanguageID? = nil) -> Bool {
        guard !contains(face.key) else { return false }
        materials.append(Material(face: face))
        if let language {
            for group in Languages.language(language).groups { pins[group] = face.key }
        }
        refreshNames()
        return true
    }

    @discardableResult public mutating func replace(
        _ old: FaceKey, with face: FaceRecord, keepAdjustments: Bool = false
    ) -> Bool {
        guard let index = index(of: old), face.key == old || !contains(face.key) else { return false }
        let material = Material(
            face: face, weight: keepAdjustments ? materials[index].weight : nil,
            scale: keepAdjustments ? materials[index].scale : nil)
        guard material != materials[index] else { return false }
        materials[index] = material
        rewriteKey(old, to: face.key)
        refreshNames()
        return true
    }

    @discardableResult public mutating func remove(_ key: FaceKey) -> Bool {
        guard let index = index(of: key) else { return false }
        let oldMain = main?.key
        materials.remove(at: index)
        if baseKey == key { baseKey = nil }
        pins = pins.filter { $0.value != key }
        resetNewMain(after: oldMain)
        refreshNames()
        return true
    }

    @discardableResult public mutating func move(_ key: FaceKey, to index: Int) -> Bool {
        guard let current = self.index(of: key) else { return false }
        let destination = min(max(0, index), materials.count - 1)
        guard current != destination else { return false }
        let oldMain = main?.key
        materials.insert(materials.remove(at: current), at: destination)
        resetNewMain(after: oldMain)
        refreshNames()
        return true
    }

    @discardableResult public mutating func setOrder(_ keys: [FaceKey]) -> Bool {
        var seen = Set<FaceKey>()
        let ordered = (keys + self.keys).compactMap { key -> Material? in
            guard seen.insert(key).inserted else { return nil }
            return material(for: key)
        }
        guard ordered != materials else { return false }
        let oldMain = main?.key
        materials = ordered
        resetNewMain(after: oldMain)
        refreshNames()
        return true
    }

    @discardableResult public mutating func setPin(_ group: ScriptGroup, to key: FaceKey?) -> Bool {
        let key = key.flatMap { contains($0) ? $0 : nil }
        guard pins[group] != key else { return false }
        pins[group] = key
        return true
    }

    @discardableResult public mutating func setAdjustments(for key: FaceKey, weight: Int?, scale: Double?) -> Bool {
        guard let index = index(of: key), materials[index].weight != weight || materials[index].scale != scale else {
            return false
        }
        materials[index].weight = weight; materials[index].scale = scale
        return true
    }

    @discardableResult public mutating func setBase(_ key: FaceKey?) -> Bool {
        let key = key.flatMap { contains($0) ? $0 : nil }
        guard baseKey != key else { return false }
        baseKey = key
        return true
    }

    @discardableResult public mutating func setDefaults(weight: Int?, scale: Double) -> Bool {
        guard defaultWeight != weight || defaultScale != scale else { return false }
        defaultWeight = weight; defaultScale = scale
        return true
    }

    @discardableResult public mutating func setFamily(_ text: String, byUser: Bool = true) -> Bool {
        let changed = names.family != text || (byUser && !names.familyEdited)
        names.family = text
        if byUser { names.familyEdited = true }
        return changed
    }

    @discardableResult public mutating func setStyle(_ text: String, byUser: Bool = true) -> Bool {
        let changed = names.style != text || (byUser && !names.styleEdited)
        names.style = text
        if byUser { names.styleEdited = true }
        return changed
    }

    @discardableResult public mutating func setSampleText(_ text: String) -> Bool {
        guard sampleText != text else { return false }
        sampleText = text
        return true
    }

    public mutating func reset() {
        let sample = sampleText
        self = Recipe()
        sampleText = sample
    }

    public mutating func refreshFileAvailability(using probe: any FileSystemProbe) -> [Int] {
        var gone: [Int] = []
        for index in materials.indices where materials[index].isAvailable {
            if probe.kind(of: materials[index].face.path) != .file {
                materials[index].availability = .fileGone
                gone.append(index)
            }
        }
        return gone
    }

    public mutating func reconcile(with catalog: FaceCatalog) -> ReconcileReport {
        var report = ReconcileReport()
        for index in materials.indices {
            let old = materials[index]
            if let face = catalog.face(for: old.key),
                face.postscriptName == old.face.postscriptName || face.postscriptName == nil
                    || old.face.postscriptName == nil
            {
                if face != old.face {
                    materials[index].face = face
                    report.refreshed.append(index)
                }
                if !old.isAvailable {
                    materials[index].availability = .available
                    report.recovered.append(index)
                }
                continue
            }
            let resolution = catalog.resolve(old.face.identity)
            let resolved: FaceRecord?
            switch resolution {
            case .byPostScriptName(let face), .byFamilyAndStyle(let face): resolved = face
            case .byPath, .unresolved: resolved = nil
            }
            if let face = resolved,
                !materials.enumerated().contains(where: { $0.offset != index && $0.element.key == face.key })
            {
                // ENGINE-8: relocation is one mutation of the material, pins and line-spacing base.
                materials[index].face = face
                materials[index].availability = .available
                rewriteKey(old.key, to: face.key)
                report.relocated.append(.init(index: index, from: old.key, to: face.key, resolution: resolution))
                if !old.isAvailable { report.recovered.append(index) }
            } else if old.isAvailable {
                // CATALOG-7: keep the last known face and all references; the user decides how to repair it.
                materials[index].availability = .fileGone
                report.nowMissing.append(index)
            }
        }
        if report.changed { refreshNames() }
        return report
    }

    private mutating func rewriteKey(_ old: FaceKey, to new: FaceKey) {
        if baseKey == old { baseKey = new }
        for group in ScriptGroup.allCases where pins[group] == old { pins[group] = new }
    }

    private mutating func resetNewMain(after old: FaceKey?) {
        if let main, main.key != old {
            materials[0].weight = nil; materials[0].scale = nil
        }
    }

    private mutating func refreshNames() {
        if !names.familyEdited { names.family = Naming.defaultFamilyName(materials.map(\.face)) }
        if !names.styleEdited { names.style = Naming.defaultStyle(main) }
    }
}
