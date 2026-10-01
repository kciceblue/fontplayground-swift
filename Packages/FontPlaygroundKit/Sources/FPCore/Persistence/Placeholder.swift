import Foundation

extension FaceRecord {
    public static func placeholder(_ identity: PortableFaceIdentity) -> FaceRecord {
        FaceRecord(
            path: identity.path, index: identity.index, family: identity.family, style: identity.style,
            coverage: .empty, glyphCount: 0, size: 0, mtime: 0, postscriptName: identity.postscriptName,
            supported: true)
    }
}
