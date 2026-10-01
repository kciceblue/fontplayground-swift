import FPCore
import Foundation
import Testing

struct LegacyImportTests {
    let a = TestFaces.a, b = TestFaces.b, c = TestFaces.c
    func load(_ json: String, catalog: FaceCatalog = FaceCatalog(TestFaces.all), probe: FakeFileSystem = .init()) -> (
        recipe: Recipe, report: LegacyRecipeReport
    ) {
        LegacyImport.recipe(fromForgeLast: Data(json.utf8), catalog: catalog, probe: probe)
    }

    @Test func toSettingsShapeImports() {
        let result = load(
            #"""
            {"materials":[{"path":"/fixtures/B.otf","index":0,"weight":null,"scale":null},
                          {"path":"/fixtures/C.ttf","index":0,"weight":null,"scale":0.8},
                          {"path":"/fixtures/A.ttf","index":0,"weight":500,"scale":null}],
             "base_index":1,"script_rules":{"latin":2,"han":0},"default_weight":400,"default_scale":1.05,
             "family_name":"Round Trip","style_name":"Bold","output_path":"C:/Users/Someone/Documents/Round Trip-Bold.ttf",
             "pins":{"latin":["/fixtures/A.ttf",0],"han":null},"names_edited":{"family":true,"style":false,"output":false},
             "sample_text":"abc"}
            """#)
        #expect(result.recipe == storedRecipe() && result.report.readable && result.report.load.isClean)
        #expect(result.report.lastSaveDirectory == nil && result.report.ignoredOutputPath == nil)
    }

    @Test func readsTheOldSchema() {
        let result = load(
            #"""
            {"materials":[{"path":"/fixtures/A.ttf","index":0,"weight":null,"scale":null},
                          {"path":"/fixtures/B.otf","index":0,"weight":null,"scale":null}],
             "base_index":0,"script_rules":{"han":0,"latin":null},"default_weight":null,"default_scale":1.0,
             "family_name":"Typed By Hand","style_name":"Regular","output_path":null}
            """#)
        let r = result.recipe
        #expect(r.pins == [.han: a.key] && r.baseKey == nil)
        #expect(r.names == RecipeNames(family: "Typed By Hand", style: "Regular", familyEdited: true))
        #expect(result.report.lastSaveDirectory == nil)
    }

    @Test func minimalFileImports() {
        let result = load(#"{"materials":[{"path":"/fixtures/A.ttf","index":0}],"sample_text":"zz"}"#)
        #expect(result.recipe.keys == [a.key] && result.recipe.sampleText == "zz")
        #expect(result.recipe.analyze().problems.isEmpty)
    }

    @Test func skipsMalformedEntriesAndDefaultsTheRest() {
        let result = load(
            #"""
            {"materials":[{"path":"/fixtures/A.ttf","index":"0"},"junk",{"path":"/fixtures/B.otf","index":"zero"},
                          {"path":5,"index":0},{"path":"/fixtures/C.ttf","index":0,"weight":"700","scale":"big"}],
             "base_index":"4","script_rules":"nope","default_weight":"500","default_scale":"wide",
             "pins":{"latin":"/fixtures/A.ttf","han":["/fixtures/A.ttf"],"hangul":["/fixtures/A.ttf","0"],
                     "kana":null,"bogus":["/fixtures/A.ttf",0],"greek":7},
             "family_name":"Typed","style_name":12,"output_path":["not","a","path"],"names_edited":"yes","sample_text":5}
            """#)
        let r = result.recipe
        #expect(r.keys == [a.key, c.key] && r.baseKey == c.key && r.pins == [.hangul: a.key])
        #expect(r.materials[1].weight == 700 && r.materials[1].scale == nil)
        #expect(r.defaultWeight == 500 && r.defaultScale == 1)
        #expect(r.names == RecipeNames(family: "Typed", familyEdited: true) && r.sampleText == Samples.defaultSample)
        #expect(r.analyze().problems.isEmpty && result.report.lastSaveDirectory == nil)
        #expect(result.report.load.outcomes == [.byPath, .malformed, .malformed, .malformed, .byPath])
        #expect(result.report.load.ignoredRules.count == 4)
    }

    @Test(arguments: [
        "null", #""text""#, "[]", #"{"materials":"not a list"}"#, #"{"materials":{"path":"x","index":0}}"#,
        #"{"materials":[null,3]}"#,
        #"{"materials":null,"pins":"latin","names_edited":[],"script_rules":[1,2],"base_index":null}"#,
        #"{"base_index":-3,"default_scale":"nan","default_weight":true,"family_name":null}"#,
    ]) func neverFailsOnMalformedInput(json: String) {
        #expect(load(json).recipe == Recipe())
    }

    @Test func oldDefaultSampleBecomesNewOne() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "materials": [["path": a.path, "index": a.index]], "sample_text": Samples.oldDefaultSample,
        ])
        let result = LegacyImport.recipe(fromForgeLast: data, catalog: FaceCatalog([a]), probe: FakeFileSystem())
        #expect(result.recipe.sampleText == Samples.defaultSample)
        #expect(
            load(#"{"materials":[{"path":"/fixtures/A.ttf","index":0}],"sample_text":"mine"}"#).recipe.sampleText
                == "mine")
    }

    var windowsJSON: String {
        #"""
        {"materials":[{"path":"C:\\Windows\\Fonts\\georgia.ttf","index":0},
                      {"path":"C:\\Windows\\Fonts\\simsun.ttc","index":0,"scale":1.05}],
         "names_edited":{"family":false,"style":false,"output":true},
         "output_path":"C:\\Users\\Someone\\Documents\\Georgia SimSun-Regular.ttf"}
        """#
    }
    var georgia: FaceRecord {
        fakeFace(cps("abc"), path: "/System/Library/Fonts/Supplemental/Georgia.ttf", family: "Georgia")
    }
    var songti: FaceRecord { fakeFace(cps("漢"), path: "/System/Library/Fonts/Songti.ttc", family: "Songti SC") }

    @Test("CRIT-2: Windows migration keeps shared fonts and unavailable identities")
    func crit2WindowsRecipeKeepsFontsThatExistOnBothSystems() {
        let result = load(windowsJSON, catalog: FaceCatalog([georgia, songti]))
        #expect(result.recipe.materials[0].face == georgia && result.report.load.outcomes[0] == .byWindowsFileName)
        #expect(
            result.recipe.materials[1].face.displayName == "SimSun Regular"
                && result.recipe.materials[1].availability == .notFound)
        #expect(result.recipe.materials[1].scale == 1.05 && result.recipe.names.family == "Georgia SimSun")
        #expect(result.report.lastSaveDirectory == nil)
        #expect(result.report.ignoredOutputPath == #"C:\Users\Someone\Documents\Georgia SimSun-Regular.ttf"#)
        #expect(result.recipe.analyze().validity == .materialUnavailable(index: 1, .notFound))
    }

    @Test("CRIT-3: Windows-only fonts offer Mac equivalents without substitution")
    func crit3WindowsOnlyFontGetsMacEquivalentSuggestions() {
        let result = load(windowsJSON, catalog: FaceCatalog([georgia, songti]))
        #expect(result.report.load.outcomes[1] == .notFound(replacements: [songti.key]))
        let pingFang = fakeFace(cps("漢"), path: "/PingFang.ttc", family: "PingFang SC")
        #expect(
            WindowsFonts.replacements(forFamily: "Microsoft YaHei", in: FaceCatalog([pingFang]), main: nil) == [
                pingFang
            ])
        #expect(WindowsFonts.replacements(forFamily: "Microsoft YaHei", in: FaceCatalog([songti]), main: nil).isEmpty)
        let menlo = fakeFace(cps("a"), path: "/Menlo.ttc", family: "Menlo")
        #expect(WindowsFonts.replacements(forFamily: "Consolas", in: FaceCatalog([menlo]), main: nil) == [menlo])
        #expect(
            EnglishText.replacementOffer(missing: "SimSun", replacement: "Songti SC")
                == "SimSun isn't on this Mac. Use Songti SC instead?")
        var privateCopy = songti;
        privateCopy.path = "/Applications/Microsoft Word.app/Contents/Resources/DFonts/Songti.ttc"
        #expect(WindowsFonts.replacements(forFamily: "SimSun", in: FaceCatalog([privateCopy]), main: nil).isEmpty)
    }

    @Test func macPathsFromTheQtAppResolveByPathOrFileName() {
        let pingFang = fakeFace(cps("漢"), path: "/bbbb.asset/AssetData/PingFang.ttc", index: 3, family: "PingFang SC")
        let result = load(
            #"""
            {"materials":[{"path":"/System/Library/Fonts/Supplemental/Georgia.ttf","index":0},
                          {"path":"/aaaa.asset/AssetData/PingFang.ttc","index":3}],
             "pins":{"han":["/aaaa.asset/AssetData/PingFang.ttc",3]},"base_index":1}
            """#, catalog: FaceCatalog([georgia, pingFang]))
        #expect(result.report.load.outcomes == [.byPath, .byFileName])
        #expect(result.recipe.keys == [georgia.key, pingFang.key])
        #expect(result.recipe.pins[.han] == pingFang.key && result.recipe.baseKey == pingFang.key)
    }

    @Test func legacySettingsImport() {
        let probe = FakeFileSystem(directories: ["/Users/Someone/MoreFonts"])
        let result = LegacyImport.settings(
            from: Data(
                #"{"extra_dirs":["D:/Fonts","/Users/Someone/MoreFonts","/Users/Someone/MoreFonts/"],"theme":"dark","preview_size":48,"colour_by_font":true}"#
                    .utf8), probe: probe)
        #expect(result.settings.extraFolders == ["/Users/Someone/MoreFonts"])
        #expect(
            result.settings.appearance == .dark && result.settings.previewPointSize == 48
                && result.settings.colourByFont)
        #expect(!result.settings.legacyImportDone && result.report.readable)
        #expect(result.report.droppedFolders == [.init(path: "D:/Fonts", reason: .windowsPath)])
        let invalid = LegacyImport.settings(from: Data(#"{"theme":"sepia","preview_size":true}"#.utf8), probe: probe)
        #expect(invalid.settings == AppSettings() && invalid.report.ignoredKeys == ["preview_size", "theme"])
        let unreadable = LegacyImport.settings(from: Data("not JSON".utf8), probe: probe)
        #expect(unreadable.settings == AppSettings() && !unreadable.report.readable)
        let types = LegacyImport.settings(
            from: Data(
                #"{"extra_dirs":[false,3],"preview_size":1.5,"colour_by_font":"true","window_geometry":7}"#.utf8),
            probe: probe)
        #expect(types.report.ignoredKeys == ["colour_by_font", "extra_dirs[0]", "extra_dirs[1]", "preview_size"])
        #expect(
            LegacyImport.legacyFolder(home: "/Users/Someone")
                == "/Users/Someone/Library/Application Support/FontPlayground")
    }

    @Test func editedOutputPathSeedsLastSaveDirectory() {
        let folder = "/Users/Someone/Fonts", probe = FakeFileSystem(directories: ["/Users/Someone/Fonts"])
        let edited = load(
            #"{"output_path":"/Users/Someone/Fonts/out.ttf","names_edited":{"output":true}}"#, probe: probe)
        #expect(edited.report.lastSaveDirectory == folder && edited.report.ignoredOutputPath == nil)
        let unedited = load(
            #"{"output_path":"/Users/Someone/Fonts/out.ttf","names_edited":{"output":false}}"#, probe: probe)
        #expect(unedited.report.lastSaveDirectory == nil && unedited.report.ignoredOutputPath == nil)
    }

    @Test func wrongShapedMaterialsAreReportedNotImportedAsEmpty() {
        for json in [#"{"materials":"not a list"}"#, #"{"materials":{"path":"/fixtures/A.ttf","index":0}}"#] {
            let result = load(json)
            #expect(result.recipe == Recipe() && result.report.readable)
            #expect(result.report.load.outcomes == [.malformed] && !result.report.load.isClean)
        }
        for json in [#"{"materials":null}"#, #"{"sample_text":"zz"}"#] {
            #expect(load(json).report.load.outcomes.isEmpty)
        }
    }

    @Test func duplicateAndMalformedIndexesAreRemappedAndCounted() {
        let result = load(
            #"""
            {"materials":[null,{"path":"/fixtures/A.ttf","index":0},{"path":"/fixtures/A.ttf","index":0},
                          {"path":"/fixtures/B.otf","index":0}],"base_index":3,"script_rules":{"han":3,"latin":2}}
            """#)
        #expect(result.report.load.outcomes == [.malformed, .byPath, .duplicate(of: 1), .byPath])
        #expect(result.recipe.keys == [a.key, b.key] && result.recipe.baseKey == b.key)
        #expect(result.recipe.pins == [.latin: a.key, .han: b.key])
        #expect(load(#"{"materials":[{"path":"/fixtures/A.ttf"}]}"#).report.load.outcomes == [.malformed])
        let missing = load(#"{"materials":[{"path":"C:/Fonts/Custom.ttf","index":0}]}"#, catalog: FaceCatalog([]))
        #expect(missing.recipe.main?.family == "Custom" && missing.report.load.unresolved.count == 1)
    }

    @Test func trailingSeparatorIsNotAFaceBasename() {
        let result = load(
            #"{"materials":[{"path":"C:/Windows/Fonts/georgia.ttf/","index":0}]}"#,
            catalog: FaceCatalog([georgia]))
        #expect(result.recipe.materials[0].availability == .notFound)
        #expect(result.report.load.outcomes == [.notFound(replacements: [])])
    }
}
