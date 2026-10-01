import Foundation
import Testing

@testable import FPCore

struct FaceCatalogTests {
    private func face(_ path: String, name: String = "FacePS", style: String = "Regular") -> FaceRecord {
        FaceRecord(path: path, family: "Face", style: style, coverage: .init(scalarsOf: "a"), postscriptName: name)
    }

    @Test func resolveFollowsArchitectureOrder() {
        let original = face("/old/font.ttf")
        let moved = face("/new/font.ttf")
        #expect(FaceCatalog([original]).resolve(original.identity) == .byPath(original))
        let replacement = face("/old/font.ttf", name: "OtherPS", style: "Bold")
        #expect(FaceCatalog([replacement, moved]).resolve(original.identity) == .byPostScriptName(moved))
        #expect(FaceCatalog([moved]).resolve(original.identity) == .byPostScriptName(moved))
        var identity = original.identity
        identity.postscriptName = nil
        #expect(FaceCatalog([moved]).resolve(identity) == .byFamilyAndStyle(moved))
        #expect(FaceCatalog([]).resolve(identity) == .unresolved)
        #expect(FaceResolution.unresolved.face == nil)
        let another = face("/another/font.ttf")
        #expect(FaceCatalog([moved, another]).resolve(original.identity).face == moved)
        identity.postscriptName = ""
        let unnamed = face("/unnamed.ttf", name: "", style: "Bold")
        #expect(FaceCatalog([unnamed, moved]).resolve(identity) == .byFamilyAndStyle(moved))
    }

    @Test func lookupsKeepCatalogOrder() {
        let a = face("/a.ttf")
        let b = face("/b.ttf", style: "Bold")
        let c = face("/c.ttf")
        let catalog = FaceCatalog([a, b, c, a])
        #expect(catalog.faces == [a, b, c])
        #expect(catalog.faces(family: "Face") == [a, b, c])
        #expect(catalog.faces(postscriptName: "FacePS") == [a, b, c])
        #expect(catalog.face(family: "Face", style: "Regular") == a)
        #expect(catalog.face(for: c.key) == c)
        #expect(catalog.faces(family: "missing").isEmpty)
        #expect(catalog.face(family: "Face", style: "Missing") == nil)
    }

    @Test func faceKeysAndPortableIdentityKeepPaths() throws {
        let path = "/System/Fonts/ヒラキ\u{3099}ノ.ttf"
        let key = FaceKey(path: path, index: 2)
        #expect(key.description == "\(path)#2")
        #expect(FaceKey(path: path, index: 1) < key)
        #expect(FaceKey(path: "/a", index: 99) < FaceKey(path: "/b", index: 0))
        #expect(try JSONDecoder().decode(FaceKey.self, from: JSONEncoder().encode(key)) == key)
        let identity = PortableFaceIdentity(postscriptName: nil, family: "Face", style: "Regular", path: path, index: 2)
        let data = try JSONEncoder().encode(identity)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["postscript_name"] is NSNull)
        let restored = try JSONDecoder().decode(PortableFaceIdentity.self, from: data)
        #expect(Array(restored.path.utf8) == Array(path.utf8))
        #expect(restored == identity && restored.key == key && restored.displayName == "Face Regular")
    }
}
