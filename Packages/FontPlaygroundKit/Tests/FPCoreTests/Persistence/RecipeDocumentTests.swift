import FPCore
import Foundation
import Testing

func storedRecipe() -> Recipe {
    let a = TestFaces.a, b = TestFaces.b, c = TestFaces.c
    var r = recipe([a, b, c])
    r.setOrder([b.key, c.key, a.key]); r.setBase(c.key); r.setPin(.latin, to: a.key)
    r.setAdjustments(for: a.key, weight: 500, scale: nil); r.setAdjustments(for: c.key, weight: nil, scale: 0.8)
    r.setDefaults(weight: 400, scale: 1.05); r.setFamily("Round Trip"); r.setSampleText("abc")
    return r
}

struct RecipeDocumentTests {
    let a = TestFaces.a, b = TestFaces.b, c = TestFaces.c

    @Test func encodesContractShape() throws {
        let first = fakeFace(cps("a"), path: "/a.ttf", family: "A", postscriptName: "A-Regular")
        let missing = PortableFaceIdentity(postscriptName: nil, family: "B", style: "Bold", path: "/b.ttf", index: 0)
        var document = RecipeDocument(recipe: recipe([first]))
        document.materials.append(.init(face: missing)); document.main = 1; document.rules = [.han: 1]
        document.names = .init(family: "Mine", familyEdited: true); document.sampleText = "abc"
        let r = document.makeRecipe(catalog: FaceCatalog([first])).recipe
        #expect(r.materials[1].availability == .notFound)
        let golden = """
            {
              "defaults" : {
                "scale" : 1,
                "weight" : null
              },
              "format" : "fontrecipe",
              "main" : 1,
              "materials" : [
                {
                  "face" : {
                    "family" : "A",
                    "index" : 0,
                    "path" : "/a.ttf",
                    "postscript_name" : "A-Regular",
                    "style" : "Regular"
                  },
                  "scale" : null,
                  "weight" : null
                },
                {
                  "face" : {
                    "family" : "B",
                    "index" : 0,
                    "path" : "/b.ttf",
                    "postscript_name" : null,
                    "style" : "Bold"
                  },
                  "scale" : null,
                  "weight" : null
                }
              ],
              "names" : {
                "family" : "Mine",
                "family_edited" : true,
                "style" : "Regular",
                "style_edited" : false
              },
              "rules" : {
                "han" : 1
              },
              "sample_text" : "abc",
              "version" : 1
            }
            """
        #expect(try RecipeDocument(recipe: r).encoded() == Data(golden.utf8))
        #expect(RecipeDocument.fileExtension == "fontrecipe" && RecipeDocument.autosaveFileName == "last.fontrecipe")
        #expect(RecipeDocument.typeIdentifier == "io.github.kciceblue.fontplayground.recipe")
    }

    @Test func roundTripKeepsEverything() throws {
        let original = storedRecipe(), document = RecipeDocument(recipe: original)
        let data = try document.encoded()
        let decoded = try RecipeDocument.decode(data)
        let (r, report) = decoded.makeRecipe(catalog: FaceCatalog(TestFaces.all))
        #expect(r == original && report.isClean)
        #expect(try RecipeDocument(recipe: r).encoded() == data)
        #expect(try JSONDecoder().decode(RecipeDocument.self, from: JSONEncoder().encode(document)) == document)
    }

    @Test("CATALOG-7: portable identity survives asset folder changes")
    func catalog7DocumentMaterialResolvesByPostScriptNameAfterPathChange() {
        let old = fakeFace(
            cps("漢"), path: "/aaaa.asset/AssetData/PingFang.ttc", index: 3, family: "PingFang SC",
            postscriptName: "PingFangSC-Regular")
        var second = a; second.postscriptName = "Old-Name"
        var r = recipe([second, old]); r.setBase(old.key); r.setPin(.han, to: old.key)
        var moved = old; moved.path = "/bbbb.asset/AssetData/PingFang.ttc"
        var newName = second; newName.path = "/new-name.ttf"; newName.postscriptName = "New-Name"
        let loaded = RecipeDocument(recipe: r).makeRecipe(catalog: FaceCatalog([moved, newName]))
        #expect(loaded.report.outcomes == [.byFamilyAndStyle, .byPostScriptName])
        #expect(loaded.recipe.keys == [newName.key, moved.key])
        #expect(loaded.recipe.pins[.han] == moved.key && loaded.recipe.baseKey == moved.key)
    }

    @Test func unresolvedMaterialIsKeptReportedAndResaved() throws {
        let original = RecipeDocument(recipe: storedRecipe())
        let (r, report) = original.makeRecipe(catalog: FaceCatalog([a, b]))
        #expect(r.keys == [b.key, c.key, a.key] && r.materials[1].availability == .notFound)
        #expect(r.baseKey == c.key && r.pins[.latin] == a.key)
        #expect(report.unresolved == [c.identity] && !report.isClean)
        #expect(EnglishText.unresolvedSummary(report) == "1 font could not be found: Fixture C Regular")
        #expect(RecipeDocument(recipe: r).materials[1].face == c.identity)
        #expect(try RecipeDocument(recipe: r).encoded() == original.encoded())
        let placeholder = r.materials[1].face
        #expect(placeholder.coverage.isEmpty && placeholder.unshaped.isEmpty && placeholder.glyphCount == 0)
        #expect(placeholder.size == 0 && placeholder.mtime == 0 && placeholder.supported)
        #expect(placeholder.upem == 1000 && placeholder.weightClass == 400)
        var recovered = r
        #expect(recovered.reconcile(with: FaceCatalog(TestFaces.all)).recovered == [1])
        #expect(recovered == storedRecipe())
    }

    @Test func versionAndShapeErrors() throws {
        let cases: [(String, RecipeDocumentError)] = [
            (#"{"format":"fontrecipe","version":2}"#, .newerVersion(2)),
            (#"{"version":1}"#, .notARecipe),
            (#"{"format":"fontrecipe","version":"1"}"#, .notARecipe),
            (#"{"format":"fontrecipe","version":0}"#, .notARecipe),
            (#"{"format":"fontrecipe","version":1,"materials":{}}"#, .malformed(field: "materials")),
            ("not json", .unreadable),
            (
                #"{"format":"fontrecipe","version":1,"names":{"family_edited":1}}"#,
                .malformed(field: "names.family_edited")
            ),
        ]
        for (json, error) in cases { #expect(throws: error) { try RecipeDocument.decode(Data(json.utf8)) } }
        let minimal = try RecipeDocument.decode(Data(#"{"format":"fontrecipe","version":1}"#.utf8))
        #expect(minimal.makeRecipe(catalog: FaceCatalog([])).recipe == Recipe())
        let extra = try RecipeDocument.decode(
            Data(
                #"{"format":"fontrecipe","version":1,"unknown":true,"names":{"extra":[1]},"defaults":{"extra":false}}"#
                    .utf8))
        #expect(extra == minimal)
        var bad = RecipeDocument(recipe: recipe())
        let data = try bad.encoded()
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var materials = try #require(object["materials"] as? [[String: Any]])
        materials[2]["weight"] = "heavy"; object["materials"] = materials
        #expect(throws: RecipeDocumentError.malformed(field: "materials[2].weight")) {
            try RecipeDocument.decode(JSONSerialization.data(withJSONObject: object))
        }
        bad.materials[0].scale = 50; bad.materials[0].weight = 1001
        #expect(
            bad.makeRecipe(catalog: FaceCatalog(TestFaces.all)).recipe.analyze().problems == [
                .scaleOutOfRange(index: 0, scale: 50), .weightOutOfRange(index: 0, weight: 1001),
            ])
    }

    @Test func oldDefaultSampleBecomesNewOne() {
        for sample in ["", Samples.oldDefaultSample, Samples.defaultSample, "mine"] {
            var document = RecipeDocument(recipe: recipe([a])); document.sampleText = sample
            let r = document.makeRecipe(catalog: FaceCatalog([a])).recipe
            #expect(r.sampleText == (sample == "mine" ? "mine" : Samples.defaultSample))
        }
    }

    @Test func rulesAndMainOutOfRangeAreReported() throws {
        let data = Data(#"{"format":"fontrecipe","version":1,"rules":{"han":9,"klingon":0},"main":7}"#.utf8)
        let (r, report) = try RecipeDocument.decode(data).makeRecipe(catalog: FaceCatalog([]))
        #expect(r.pins.isEmpty && report.ignoredRules == ["han=9", "klingon=0"])
        #expect(report.mainOutOfRange && r.baseKey == nil && !report.isClean)
    }

    @Test func duplicateResolutionIsReported() {
        var document = RecipeDocument(recipe: recipe([a, b, c]))
        document.materials.insert(.init(face: a.identity), at: 1)
        document.main = 3; document.rules = [.latin: 1, .han: 2]
        let (r, report) = document.makeRecipe(catalog: FaceCatalog(TestFaces.all))
        #expect(r.keys == [a.key, b.key, c.key])
        #expect(report.outcomes == [.byPath, .duplicate(of: 0), .byPath, .byPath])
        #expect(r.baseKey == c.key && r.pins == [.latin: a.key, .han: b.key])
        let missing = document.makeRecipe(catalog: FaceCatalog([]))
        #expect(missing.recipe.keys == [a.key, b.key, c.key] && missing.report.outcomes[1] == .duplicate(of: 0))
        #expect(missing.recipe.analyze().problems.count == 3)
    }
}
