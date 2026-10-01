import FPCore
import Foundation
import Testing

func recipe(_ faces: [FaceRecord] = TestFaces.all) -> Recipe {
    var value = Recipe()
    for face in faces { value.add(face) }
    return value
}

struct RecipeOperationsTests {
    let a = TestFaces.a, b = TestFaces.b, c = TestFaces.c
    let unknown = FaceKey(path: "nope", index: 0)

    @Test func addRemoveMoveAndSetOrder() {
        var r = Recipe()
        #expect(r.add(a) && r.add(b) && r.add(c))
        #expect(r.add(a) == false)
        #expect(r.keys == [a.key, b.key, c.key])
        #expect(r.main == a && r.materials[1] == Material(face: b))
        #expect(r.contains(b.key) && r.index(of: c.key) == 2)
        #expect(r.move(c.key, to: 0) && r.keys == [c.key, a.key, b.key])
        #expect(!r.move(c.key, to: 0) && !r.move(unknown, to: 1))
        #expect(r.move(c.key, to: 99) && r.keys == [a.key, b.key, c.key])
        #expect(r.setOrder([b.key, unknown, b.key, a.key]) && r.keys == [b.key, a.key, c.key])
        #expect(r.setOrder([b.key, a.key, c.key]) == false)
        #expect(r.setOrder([c.key]) && r.keys == [c.key, b.key, a.key])
        #expect(r.remove(b.key) && r.keys == [c.key, a.key])
        #expect(!r.remove(b.key) && r.material(for: b.key) == nil)
        #expect(r.material(for: a.key)?.face == a)
    }

    @Test func newMainDropsSizeAndWeight() {
        var r = recipe()
        r.setAdjustments(for: b.key, weight: 700, scale: 1.1)
        r.setAdjustments(for: c.key, weight: 600, scale: 0.9)
        #expect(r.move(b.key, to: 0) && r.materials[0] == Material(face: b))
        #expect(r.material(for: c.key) == Material(face: c, weight: 600, scale: 0.9))
        r.setAdjustments(for: a.key, weight: 500, scale: 1.2)
        #expect(r.move(c.key, to: 1) && r.material(for: c.key)?.weight == 600)
        #expect(r.setOrder([c.key]) && r.materials[0] == Material(face: c))
        r.setAdjustments(for: b.key, weight: 300, scale: 0.8)
        #expect(r.remove(c.key) && r.materials[0] == Material(face: b))
        #expect(r.material(for: a.key) == Material(face: a, weight: 500, scale: 1.2))
    }

    @Test func removeClearsBaseAndPins() {
        var r = recipe([a, b])
        #expect(r.setBase(b.key) && r.baseKey == b.key && r.base == b && r.baseIndex == 1)
        #expect(r.setPin(.latin, to: b.key) && r.setPin(.han, to: a.key))
        r.remove(b.key)
        #expect(r.baseKey == nil && r.base == a && r.baseIndex == 0)
        #expect(r.pins[.latin] == nil && r.pins[.han] == a.key)
        r.remove(a.key)
        #expect(r.base == nil && r.baseIndex == nil && r.main == nil)
    }

    @Test func pinsBaseAdjustAndDefaults() {
        var r = recipe([a, b])
        #expect(ScriptGroup(rawValue: "no-such-group") == nil)
        #expect(r.setPin(.latin, to: nil) == false)
        #expect(r.setPin(.latin, to: b.key) && !r.setPin(.latin, to: b.key))
        #expect(r.setPin(.han, to: unknown) == false)
        #expect(r.setPin(.latin, to: unknown) && r.pins[.latin] == nil)
        #expect(r.setAdjustments(for: b.key, weight: 500, scale: 1.2) == true)
        #expect(r.material(for: b.key) == Material(face: b, weight: 500, scale: 1.2))
        #expect(r.setAdjustments(for: b.key, weight: 500, scale: 1.2) == false)
        #expect(r.setAdjustments(for: unknown, weight: 1, scale: 1) == false)
        #expect(!r.setBase(unknown) && r.setBase(a.key) && r.baseKey == a.key)
        #expect(r.setDefaults(weight: 700, scale: 0.9) == true)
        #expect(r.defaultWeight == 700 && r.defaultScale == 0.9)
        #expect(r.setDefaults(weight: 700, scale: 0.9) == false)
        #expect(r.setDefaults(weight: nil, scale: 1) == true)
    }

    @Test func resetKeepsSampleText() {
        var r = recipe([a, b])
        r.setBase(b.key); r.setPin(.latin, to: b.key)
        r.setAdjustments(for: a.key, weight: 500, scale: 1.2)
        r.setDefaults(weight: 700, scale: 0.9)
        r.setFamily("Mine"); r.setStyle("Heavy"); r.setSampleText("keep me")
        r.reset()
        var empty = Recipe(); empty.setSampleText("keep me")
        #expect(r == empty)
        r.add(c)
        #expect(r.names.family == "Fixture C Forged" && r.names.style == "Regular")
    }

    @Test func addForALanguagePinsItsGroups() {
        let kana = fakeFace(cps("あいうえおかきくけこab"), path: "kana.ttf", family: "Kana")
        var r = recipe([a])
        r.add(b, for: .chineseSimplified)
        #expect(r.pins == [.han: b.key])
        r.add(kana, for: .japanese)
        #expect(r.pins[.kana] == kana.key && r.scriptRules()[.kana] == 2)
        r.add(c)
        #expect(r.pins[.latin] == nil)
        #expect(LanguageID(rawValue: "no such language") == nil)
        r.add(fakeFace(cps("x"), path: "x.ttf"), for: nil)
        #expect(r.materials.count == 5)
    }

    @Test func replaceKeepsPositionAndMovesPinsAndBase() {
        var r = recipe()
        r.setPin(.han, to: b.key); r.setBase(b.key)
        r.setAdjustments(for: b.key, weight: 700, scale: 1.1)
        let new = fakeFace(cps("ab漢"), path: "new.ttf", family: "New")
        #expect(r.replace(b.key, with: new) == true)
        #expect(r.keys == [a.key, new.key, c.key])
        #expect(r.pins[.han] == new.key && r.baseKey == new.key)
        #expect(r.materials[1] == Material(face: new))
        #expect(!r.replace(new.key, with: a) && !r.replace(unknown, with: a))
        var bold = new; bold.style = "Bold"; bold.index = 1
        r.setAdjustments(for: new.key, weight: 600, scale: 0.9)
        #expect(r.replace(new.key, with: bold, keepAdjustments: true) == true)
        #expect(r.materials[1] == Material(face: bold, weight: 600, scale: 0.9))
        #expect(r.replace(bold.key, with: bold, keepAdjustments: true) == false)
        _ = r.refreshFileAvailability(using: FakeFileSystem())
        #expect(r.replace(bold.key, with: bold, keepAdjustments: true) == true)
        #expect(r.materials[1].isAvailable)
    }

    @Test func snapshotsAreIndependentAndCodable() throws {
        let original = recipe()
        var copy = original
        copy.setPin(.han, to: a.key); copy.remove(b.key); copy.setFamily("Changed")
        #expect(original == recipe())
        #expect(try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(copy)) == copy)
    }
}
