import FPCore
import Testing

struct ValidityTests {
    let a = TestFaces.a, b = TestFaces.b, c = TestFaces.c
    var bad: FaceRecord { fakeFace(c.coverage, path: c.path, family: "Fixture Z", outline: .cff2) }
    func text(_ r: Recipe) -> String { r.analyze().validity.map { EnglishText.problem($0, in: r) } ?? "" }

    @Test func validityWording() {
        var r = Recipe()
        #expect(text(r) == "Add at least one font.")
        r.add(a); #expect(text(r).isEmpty)
        r.setFamily("   "); #expect(text(r) == "Family name is empty.")
        r.setFamily("Ok"); #expect(text(r).isEmpty)
        r.setStyle(""); #expect(text(r) == "Style name is empty.")
        r.setStyle("Regular"); r.add(bad)
        #expect(text(r) == "Fixture Z Regular: CFF2 outlines are not supported")
        r.remove(bad.key); r.setAdjustments(for: a.key, weight: nil, scale: 50)
        #expect(text(r) == "Fixture A Regular: scale 50 must be between 0.1 and 10.")
        r.remove(a.key); #expect(text(r) == "Add at least one font.")
    }

    @Test func problemsInReferenceOrder() {
        var r = Recipe()
        #expect(r.analyze().problems == [.empty])
        r.add(a); r.add(c); r.setBase(c.key); r.setAdjustments(for: a.key, weight: nil, scale: 9)
        #expect(text(r) == "Fixture A Regular: scale 900% is too large for a 2048-unit base (maximum 800%).")
        r.setAdjustments(for: a.key, weight: 1001, scale: nil)
        #expect(r.analyze().validity == .weightOutOfRange(index: 0, weight: 1001))
        #expect(text(r) == "Fixture A Regular: weight 1001 must be between 1 and 1000.")
        r.setAdjustments(for: a.key, weight: nil, scale: nil); r.setFamily(" .Hidden")
        #expect(r.analyze().validity == .familyNameStartsWithDot)
        #expect(text(r) == "Family name can't start with “.”: macOS hides fonts whose names start with a dot.")
        r.setFamily("Bad\u{07}Name")
        #expect(r.analyze().validity == .familyNameHasControlCharacter)
        #expect(text(r) == "Family name contains a control character.")
        r.setFamily("\u{1C}Name\u{3000}")
        #expect(r.analyze().problems.isEmpty)
        r.setStyle("Bold\u{1B}")
        #expect(r.analyze().validity == .styleNameHasControlCharacter)
        #expect(text(r) == "Style name contains a control character.")
        r = recipe([a, b, bad]); r.setFamily(".X"); r.setStyle("")
        r.setAdjustments(for: a.key, weight: nil, scale: 50)
        #expect(
            r.analyze().problems == [
                .unsupported(index: 2, reason: bad.unsupportedReason), .styleNameEmpty, .familyNameStartsWithDot,
                .scaleOutOfRange(index: 0, scale: 50),
            ])
        _ = r.refreshFileAvailability(using: FakeFileSystem(files: [b.path]))
        #expect(
            Array(r.analyze().problems.prefix(2)) == [
                .materialUnavailable(index: 0, .fileGone), .materialUnavailable(index: 2, .fileGone),
            ])
    }

    @Test func fileThatVanishedIsFlagged() {
        var r = recipe([a]); var files = FakeFileSystem(files: [a.path])
        #expect(r.refreshFileAvailability(using: files).isEmpty)
        files.files.remove(a.path)
        #expect(r.refreshFileAvailability(using: files) == [0])
        #expect(text(r) == "Fixture A Regular: the font file is no longer there" && !r.analyze().canForge)
        files.files.insert(a.path)
        #expect(r.refreshFileAvailability(using: files).isEmpty && !r.materials[0].isAvailable)
        #expect(r.reconcile(with: FaceCatalog([a])).recovered == [0])
    }

    @Test func emptyRecipeCannotForge() {
        #expect(Recipe().analyze().validity == .empty && !Recipe().analyze().canForge)
    }

    @Test func scaleAndWeightBoundsUseEngineRoundingAndDefaults() {
        var r = recipe([a])
        for scale in [0.1, 10.0] {
            for weight in [1, 1000] {
                r.setDefaults(weight: weight, scale: scale)
                #expect(r.analyze().problems.isEmpty)
            }
        }
        r.setDefaults(weight: 0, scale: 0.09)
        #expect(
            r.analyze().problems == [.scaleOutOfRange(index: 0, scale: 0.09), .weightOutOfRange(index: 0, weight: 0)])
        r = recipe([a, c]); r.setBase(c.key)
        r.setAdjustments(for: a.key, weight: nil, scale: 16384.5 / 2048)
        #expect(r.analyze().problems.isEmpty)
        r.setAdjustments(for: a.key, weight: nil, scale: 16385 / 2048.0)
        #expect(r.analyze().problems == [.scaleTooLarge(index: 0, scale: 16385 / 2048.0, baseUPM: 2048)])
    }

    @Test func specValidationProblems() {
        let first = fakeFace(cps("abc"), path: "a.ttf", family: "A")
        let second = fakeFace(cps("ab漢"), path: "b.otf", family: "B", weight: 700)
        var spec = ForgeSpec(
            materials: [.init(path: first.path), .init(path: second.path, weight: 500, scale: 0.9)],
            scriptRules: [.han: 1])
        #expect(SpecValidation.problems(spec, faces: [first, second]).isEmpty)
        spec.familyName = " "; spec.baseIndex = 5; spec.scriptRules[.greek] = 9
        let bitmap = fakeFace(cps("a"), family: "Bmp", outline: .none)
        spec.materials.append(.init(path: bitmap.path))
        #expect(
            SpecValidation.problems(spec, faces: [first, second, bitmap]) == [
                .baseOutOfRange, .unsupported(index: 2, reason: "bitmap-only font (no outlines)"), .familyNameEmpty,
                .ruleOutOfRange(.greek),
            ])
        #expect(SpecValidation.problems(ForgeSpec(), faces: []) == [.empty])
        #expect(EnglishText.problem(.baseOutOfRange, in: Recipe()) == "Base material is out of range.")
        #expect(
            EnglishText.problem(.ruleOutOfRange(.greek), in: Recipe()) == "Rule for greek points to a missing material."
        )
    }

    @Test func cannotShapeFollowsTheEngineRule() {
        let arabic = CodepointSet(ranges: [0x627...0x64A])
        let main = fakeFace(cps("abc"))
        let geeza = fakeFace(
            cps("ab").union(arabic), path: "geeza.ttc", family: "Geeza Pro", unshaped: arabic, shapesGroups: [],
            aat: .init(morx: true))
        let damascus = fakeFace(arabic, path: "damascus.ttc", family: "Damascus", shapesGroups: [.arabic])
        var automatic = recipe([main, geeza]); automatic.setSampleText("مرحبا")
        #expect(automatic.analyze().problems.isEmpty && automatic.scriptRules()[.arabic] == nil)
        #expect(Set(automatic.missingSampleCharacters()) == Set("مرحبا".unicodeScalars))
        var pinned = recipe([main]); pinned.add(geeza, for: .arabic); pinned.setSampleText("مرحبا")
        #expect(pinned.analyze().problems == [.cannotShape(index: 1, group: .arabic)] && !pinned.analyze().canForge)
        #expect(
            text(pinned)
                == "Geeza Pro Regular can't draw Arabic in the forged font: it shapes it with Apple-only rules (AAT) that can't be carried over. Choose another font for Arabic."
        )
        #expect(SpecValidation.problems(pinned.forgeSpec(), faces: pinned.materials.map(\.face)).isEmpty)
        var safe = recipe([main]); safe.add(damascus, for: .arabic); safe.setSampleText("مرحبا")
        #expect(safe.analyze().problems.isEmpty && safe.missingSampleCharacters().isEmpty)
        let unknown = fakeFace(cps("ab").union(arabic), path: "geeza.ttc", family: "Geeza Pro", aat: .init(morx: true))
        pinned.replace(geeza.key, with: unknown)
        #expect(pinned.analyze().problems.isEmpty)
        let noRules = fakeFace(arabic, path: "bare.ttf", family: "Bare", unshaped: arabic, shapesGroups: [])
        pinned.replace(unknown.key, with: noRules)
        #expect(
            text(pinned)
                == "Bare Regular can't draw Arabic in the forged font: it has no OpenType shaping rules for it. Choose another font for Arabic."
        )
        _ = pinned.refreshFileAvailability(using: FakeFileSystem(files: [main.path]))
        #expect(!pinned.analyze().problems.contains(.cannotShape(index: 1, group: .arabic)))
    }
}
