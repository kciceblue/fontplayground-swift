import FPCore
import Foundation
import Testing

@testable import FPAppUI

struct RecipeColumnTextTests {
    @Test func scaleAndWeightHelpers() {
        #expect(RecipeText.scalePercent(nil) == 100); #expect(RecipeText.scalePercent(1.2) == 120);
        #expect(RecipeText.scalePercent(0.95) == 95)
        #expect(RecipeText.scalePercent(1e20) == Int(Int32.max) && RecipeText.scalePercent(-1e20) == -Int(Int32.max))
        #expect(RecipeText.scalePercent(.infinity) == 100 && RecipeText.scalePercent(.nan) == 100)
        #expect(RecipeText.percentScale(100) == nil); #expect(RecipeText.percentScale(120) == 1.2)
        #expect(RecipeText.weightChoices.map(\.0) == [nil, 300, 400, 500, 600, 700, 900])
        #expect(
            RecipeText.weightChoices.map(\.1) == [
                "As is", "Light (300)", "Regular (400)", "Medium (500)", "Semibold (600)", "Bold (700)", "Heavy (900)",
            ])
    }
    @Test func tallyLanguagePrefersLargestNamedGroup() {
        let rows: [([ScriptGroup: Int], String)] = [
            ([.han: 20_000, .kana: 300, .cjkSymbols: 500], "chinese_s"),
            ([.symbols: 900, .greek: 60], "greek"), ([.symbols: 900, .emoji: 12], "symbols"),
            ([.hangul: 2000], "korean"), ([.other: 30], "any"), ([:], "any"),
        ]
        for (tally, language) in rows { #expect(RecipeText.tallyLanguage(tally) == language) }
    }
    @Test func familyStylesLightestFirst() throws {
        let regular = try RecipeTestFaces.make("r.ttf", family: "Fake", chars: "ab")
        let bold = try RecipeTestFaces.make("b.ttf", family: "Fake", chars: "ab", style: "Bold", weight: 700)
        let light = try RecipeTestFaces.make("l.ttf", family: "Fake", chars: "ab", style: "Light", weight: 300)
        let black = try RecipeTestFaces.make(
            "x.ttf", family: "Fake", chars: "ab", style: "Black", weight: 900, fields: ["outline": "none"])
        let other = try RecipeTestFaces.make("o.ttf", family: "Other", chars: "ab")
        #expect(
            RecipeText.familyStyles(regular, [bold, regular, black, other, light]).map(\.style) == [
                "Light", "Regular", "Bold",
            ])
        #expect(RecipeText.familyStyles(other, [regular]) == [other])
    }
    @Test func offListWeightShownAsNumber() {
        let items = RecipeText.weightMenuItems(selected: 650, locale: Locale(identifier: "en_US"))
        #expect(items.count == 8); #expect(items.last?.0 == 650); #expect(items.last?.1 == "650")
        #expect(RecipeText.weightMenuItems(selected: 1101, locale: Locale(identifier: "en_US")).last?.1 == "1,101")
    }
    @Test func accessibilityLabels() {
        #expect(
            RecipeText.cardAccessibilityLabel(role: "MAIN FONT", family: "Fixture A", style: "Regular")
                == "MAIN FONT: Fixture A Regular")
        #expect(RecipeText.moreActionsAccessibilityLabel(family: "Fixture B") == "More actions for Fixture B")
        #expect(RecipeText.sizeAccessibilityLabel(family: "Fixture B") == "Size of Fixture B, percent")
        #expect(RecipeText.weightAccessibilityLabel(family: "Fixture B") == "Weight of Fixture B")
    }
}
