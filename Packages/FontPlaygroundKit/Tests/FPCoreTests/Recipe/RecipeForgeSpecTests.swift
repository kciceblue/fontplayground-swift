import FPCore
import Foundation
import Testing

struct RecipeForgeSpecTests {
    let a = TestFaces.a, b = TestFaces.b

    @Test func forgeSpecReflectsRowsRulesAndNames() {
        var r = recipe([a, b])
        r.setAdjustments(for: a.key, weight: 300, scale: nil)
        r.setBase(b.key); r.setPin(.latin, to: b.key)
        r.setDefaults(weight: 600, scale: 1.1); r.setFamily("Mixed"); r.setStyle("Italic")
        let spec = r.forgeSpec()
        #expect(spec.materials.map(\.path) == [a.path, b.path])
        #expect(spec.materials[0].weight == 300 && spec.materials[0].scale == nil)
        #expect(spec.baseIndex == 1 && spec.scriptRules[.latin] == 1 && spec.scriptRules[.han] == 1)
        #expect(spec.scriptRules[.hangul] == nil)
        #expect(spec.defaultWeight == 600 && spec.defaultScale == 1.1)
        #expect(spec.familyName == "Mixed" && spec.styleName == "Italic")
        #expect(r.analyze().problems.isEmpty)
        r.setOrder([b.key, a.key])
        #expect(r.forgeSpec().baseIndex == 0 && r.forgeSpec().scriptRules[.latin] == 0)
    }

    @Test("ENGINE-8: every forged material carries stale-file expectations")
    func engine8ForgeSpecCarriesExpectForStaleDetection() throws {
        var named = a; named.postscriptName = "FixtureA-Regular"
        let r = recipe([named, b])
        let request = r.forgeRequest(outputPath: "/tmp/forged.ttf")
        #expect(request.spec == r.forgeSpec() && request.outputPath == "/tmp/forged.ttf")
        let json = try #require(JSONSerialization.jsonObject(with: request.encodedJSON()) as? [String: Any])
        let spec = try #require(json["spec"] as? [String: Any])
        let materials = try #require(spec["materials"] as? [[String: Any]])
        for (i, face) in [named, b].enumerated() {
            #expect(
                request.spec.materials[i].expect
                    == .init(postscriptName: face.postscriptName, size: face.size, mtime: face.mtime))
            let expect = try #require(materials[i]["expect"] as? [String: Any])
            #expect(expect["size"] as? Int == face.size && expect["mtime"] as? Double == face.mtime)
            if let name = face.postscriptName {
                #expect(expect["postscript_name"] as? String == name)
            } else {
                #expect(expect["postscript_name"] is NSNull)
            }
        }
    }

    @Test func specEqualityDefinesStaleness() {
        var r = recipe([a, b])
        let before = r.forgeSpec()
        r.setSampleText("Only the preview changed")
        #expect(r.forgeSpec() == before)
        #expect(r.setFamily(r.names.family) && r.forgeSpec() == before)
        #expect(!r.reconcile(with: FaceCatalog([a, b])).changed && r.forgeSpec() == before)
        r.setStyle("Other")
        #expect(r.forgeSpec() != before)
        let renamed = r.forgeSpec()
        r.setAdjustments(for: b.key, weight: 500, scale: 1.2)
        #expect(r.forgeSpec() != renamed)
        let adjusted = r.forgeSpec()
        var rescan = a; rescan.mtime += 1
        #expect(r.reconcile(with: FaceCatalog([rescan, b])).refreshed == [0])
        #expect(r.forgeSpec() != adjusted)
    }
}
