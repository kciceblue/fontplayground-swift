import FPCore
import Testing

struct RecipeNamesTests {
    @Test func namesAreProposedUntilTheUserEditsThem() {
        let a = TestFaces.a, b = TestFaces.b, c = TestFaces.c
        var r = Recipe()
        #expect(r.names == RecipeNames() && r.suggestedFileName == "Forged-Regular.ttf")
        r.add(b)
        #expect(r.names.family == "Fixture B Forged" && r.names.style == "Bold")
        #expect(r.suggestedFileName == "Fixture B Forged-Bold.ttf")
        r.add(a)
        #expect(r.names.family == "Fixture B Fixture A")
        r.setOrder([a.key, b.key])
        #expect(r.names == RecipeNames(family: "Fixture A Fixture B", style: "Regular"))
        #expect(r.setFamily("Mine") && r.names.familyEdited)
        #expect(r.suggestedFileName == "Mine-Regular.ttf")
        r.add(c)
        #expect(r.suggestedFileName == "Mine-Regular.ttf")
        r.setStyle("Heavy", byUser: false)
        #expect(!r.names.styleEdited && r.suggestedFileName == "Mine-Heavy.ttf")
        r.setOrder([b.key, a.key, c.key])
        #expect(r.names.style == "Bold")
        r.setStyle("Custom"); r.remove(a.key)
        #expect(r.names.family == "Mine" && r.names.style == "Custom")
        #expect(!r.setStyle("Custom") && !r.setFamily("Mine"))
        r.setStyle("Temporary", byUser: false)
        #expect(r.names.styleEdited)
        r.setPin(.latin, to: c.key); r.setBase(c.key)
        r.setAdjustments(for: c.key, weight: 600, scale: 1.2); r.setDefaults(weight: 300, scale: 0.8)
        #expect(r.names.style == "Temporary")
    }
}
