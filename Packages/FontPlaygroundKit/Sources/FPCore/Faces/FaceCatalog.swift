import Foundation

public struct FaceCatalog: Sendable {
    public let faces: [FaceRecord]
    private let byKey: [FaceKey: FaceRecord]
    private let byPostScriptName: [String: [FaceRecord]]
    private let byFamily: [String: [FaceRecord]]

    public init(_ faces: [FaceRecord]) {
        var ordered: [FaceRecord] = []
        var keys: [FaceKey: FaceRecord] = [:]
        var names: [String: [FaceRecord]] = [:]
        var families: [String: [FaceRecord]] = [:]
        for face in faces where keys[face.key] == nil {
            ordered.append(face)
            keys[face.key] = face
            if let name = face.postscriptName { names[name, default: []].append(face) }
            families[face.family, default: []].append(face)
        }
        self.faces = ordered
        byKey = keys
        byPostScriptName = names
        byFamily = families
    }

    public func face(for key: FaceKey) -> FaceRecord? { byKey[key] }
    public func faces(postscriptName: String) -> [FaceRecord] { byPostScriptName[postscriptName] ?? [] }
    public func faces(family: String) -> [FaceRecord] { byFamily[family] ?? [] }
    public func face(family: String, style: String) -> FaceRecord? {
        byFamily[family]?.first { $0.style == style }
    }

    public func resolve(_ identity: PortableFaceIdentity) -> FaceResolution {
        if let face = byKey[identity.key],
            identity.postscriptName == nil || face.postscriptName == identity.postscriptName
        {
            return .byPath(face)
        }
        // ENGINE-8: an AssetsV2 update can move the same face to a different hash directory.
        if let name = identity.postscriptName, !name.isEmpty, let face = byPostScriptName[name]?.first {
            return .byPostScriptName(face)
        }
        if let face = face(family: identity.family, style: identity.style) {
            return .byFamilyAndStyle(face)
        }
        return .unresolved
    }
}

public enum FaceResolution: Sendable, Equatable {
    case byPath(FaceRecord), byPostScriptName(FaceRecord), byFamilyAndStyle(FaceRecord), unresolved

    public var face: FaceRecord? {
        switch self {
        case .byPath(let face), .byPostScriptName(let face), .byFamilyAndStyle(let face): face
        case .unresolved: nil
        }
    }
}
