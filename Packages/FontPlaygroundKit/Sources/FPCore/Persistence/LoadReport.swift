import Foundation

public struct LoadReport: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case byPath, byPostScriptName, byFamilyAndStyle, byWindowsFileName, byFileName
        case notFound(replacements: [FaceKey])
        case duplicate(of: Int)
        case malformed
    }
    public var outcomes: [Outcome] = []
    public var unresolved: [PortableFaceIdentity] = []
    public var ignoredRules: [String] = []
    public var mainOutOfRange = false
    public var isClean: Bool { outcomes.allSatisfy { $0 == .byPath } && ignoredRules.isEmpty && !mainOutOfRange }
    public init() {}
}

// Keep original positions separate from kept rows so every duplicate and malformed entry is accounted for.
struct RecipeLoader {
    var materials: [Material] = []
    var report = LoadReport()
    var remap: [Int: Int] = [:]
    var originalKeys: [FaceKey: Int] = [:]
    private var firstPositions: [FaceKey: Int] = [:]
    private var firstResolved: FaceRecord?

    mutating func append(
        identity: PortableFaceIdentity, face: FaceRecord?, outcome: LoadReport.Outcome?,
        weight: Int?, scale: Double?, position: Int, catalog: FaceCatalog
    ) {
        let key = face?.key ?? identity.key
        if let earlier = firstPositions[key] {
            remap[position] = remap[earlier]
            originalKeys[identity.key] = remap[earlier]
            report.outcomes.append(.duplicate(of: earlier))
            return
        }
        firstPositions[key] = position
        remap[position] = materials.count
        originalKeys[identity.key] = materials.count
        if let face {
            materials.append(Material(face: face, weight: weight, scale: scale))
            report.outcomes.append(outcome ?? .byPath)
            if firstResolved == nil { firstResolved = face }
        } else {
            materials.append(
                Material(face: .placeholder(identity), weight: weight, scale: scale, availability: .notFound))
            report.outcomes.append(
                .notFound(
                    replacements: WindowsFonts.replacements(
                        forFamily: identity.family, in: catalog, main: firstResolved
                    ).map(\.key)))
            report.unresolved.append(identity)
        }
    }

    mutating func base(_ original: Int) -> FaceKey? {
        guard let index = remap[original] else {
            report.mainOutOfRange = original != 0
            return nil
        }
        return index > 0 ? materials[index].key : nil
    }

    mutating func rules(_ raw: [String: JSONValue], tolerant: Bool) -> [ScriptGroup: FaceKey] {
        var pins: [ScriptGroup: FaceKey] = [:]
        for (name, value) in raw.sorted(by: { $0.key < $1.key }) {
            if value == .null { continue }
            let index: Int?
            if tolerant {
                index = value.asInt
            } else if case .integer(let integer) = value {
                index = integer
            } else {
                index = nil
            }
            if let group = ScriptGroup(rawValue: name), let index, let newIndex = remap[index] {
                pins[group] = materials[newIndex].key
            } else {
                report.ignoredRules.append("\(name)=\(value.description)")
            }
        }
        return pins
    }
}
