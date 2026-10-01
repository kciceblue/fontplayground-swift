import FPCore
import Foundation
import Testing

struct ReconcileTests {
    let a = TestFaces.a, b = TestFaces.b, c = TestFaces.c

    @Test("ENGINE-8: moved assets resolve by PostScript name") func engine8MovedAssetPathIsReresolvedByPostScriptName()
    {
        let path = "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/aaaa.asset/AssetData/PingFang.ttc"
        let face = fakeFace(cps("漢"), path: path, index: 3, family: "PingFang SC", postscriptName: "PingFangSC-Regular")
        var r = recipe([a, face]); r.setPin(.han, to: face.key); r.setBase(face.key)
        r.setAdjustments(for: face.key, weight: 500, scale: 1.1)
        var moved = face; moved.path = path.replacingOccurrences(of: "aaaa", with: "bbbb")
        let report = r.reconcile(with: FaceCatalog([a, moved]))
        #expect(report.changed && report.relocated.count == 1)
        #expect(
            report.relocated.first
                == .init(index: 1, from: face.key, to: moved.key, resolution: .byPostScriptName(moved)))
        #expect(r.materials[1] == Material(face: moved, weight: 500, scale: 1.1))
        #expect(r.pins[.han] == moved.key && r.baseKey == moved.key && r.analyze().problems.isEmpty)
    }

    @Test("ENGINE-8: vanished materials remain visible and reported") func engine8VanishedMaterialIsKeptAndReported()
        throws
    {
        var r = recipe([a, b]); r.setPin(.han, to: b.key); r.setBase(b.key); r.setSampleText("漢")
        let report = r.reconcile(with: FaceCatalog([a]))
        #expect(report.nowMissing == [1] && report.changed)
        #expect(r.keys == [a.key, b.key] && r.materials[1].availability == .fileGone)
        #expect(r.pins[.han] == b.key && r.baseKey == b.key)
        #expect(r.analyze().validity == .materialUnavailable(index: 1, .fileGone))
        #expect(
            EnglishText.problem(try #require(r.analyze().validity), in: r)
                == "Fixture B Bold: the font file is no longer there")
        #expect(r.analyze().missingSampleCharacters == ["漢"])
        #expect(!r.reconcile(with: FaceCatalog([a])).changed)
        #expect(r.reconcile(with: FaceCatalog([a, b])).recovered == [1])
        #expect(r.analyze().problems.isEmpty)
    }

    @Test func setCatalogRefreshesChangedFaces() {
        var r = recipe([a, b]); r.setPin(.han, to: b.key); r.setBase(b.key)
        let original = r.forgeSpec()
        #expect(!r.reconcile(with: FaceCatalog([a, b, c])).changed && r.forgeSpec() == original)
        var rescanned = a; rescanned.mtime += 1
        #expect(r.reconcile(with: FaceCatalog([rescanned, b])).refreshed == [0])
        #expect(r.main == rescanned && r.forgeSpec() != original)
        #expect(r.reconcile(with: FaceCatalog([rescanned, c])).nowMissing == [1])
        #expect(r.keys == [a.key, b.key] && r.pins[.han] == b.key && r.baseKey == b.key)
        #expect(r.names.family == "Fixture A Fixture B")
    }

    @Test func relocationDoesNotDuplicateAnotherMaterialAndRecoveryKeepsAdjustments() {
        var first = a; first.postscriptName = "Shared"
        var other = b; other.postscriptName = "Shared"
        var r = recipe([first, other])
        r.setAdjustments(for: first.key, weight: 550, scale: 1.2)
        #expect(r.reconcile(with: FaceCatalog([other])).nowMissing == [0])
        #expect(r.keys == [first.key, other.key])
        var moved = first; moved.path = "moved.ttf"
        let report = r.reconcile(with: FaceCatalog([moved, other]))
        #expect(report.relocated.count == 1 && report.recovered == [0])
        #expect(r.materials[0] == Material(face: moved, weight: 550, scale: 1.2))
        var impostor = first; impostor.postscriptName = "Different"; impostor.family = "Different"
        var lonely = recipe([first])
        #expect(lonely.reconcile(with: FaceCatalog([impostor])).nowMissing == [0])
        #expect(lonely.main == first)
    }

    @Test func notFoundSurvivesRefreshAndRecoversByFamilyAndStyle() throws {
        let original = recipe([a])
        var snapshot = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var materials = try #require(snapshot["materials"] as? [[String: Any]])
        materials[0]["availability"] = "notFound"
        snapshot["materials"] = materials
        var r = try JSONDecoder().decode(Recipe.self, from: JSONSerialization.data(withJSONObject: snapshot))
        #expect(!r.reconcile(with: FaceCatalog([])).changed)
        #expect(r.materials[0].availability == .notFound)
        #expect(
            EnglishText.problem(.materialUnavailable(index: 0, .notFound), in: r)
                == "Fixture A Regular: this font is not on this Mac")
        #expect(r.refreshFileAvailability(using: FakeFileSystem(files: [a.path])).isEmpty)
        var moved = a; moved.path = "new-location.ttf"
        let report = r.reconcile(with: FaceCatalog([moved]))
        #expect(report.recovered == [0] && report.relocated.first?.resolution == .byFamilyAndStyle(moved))
        #expect(r.materials[0].isAvailable)
    }
}
