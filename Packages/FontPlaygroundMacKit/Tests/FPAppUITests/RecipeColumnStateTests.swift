import AppKit
import FPCore
import Foundation
import Testing

@testable import FPAppUI

@MainActor struct RecipeColumnStateTests {
    @Test func emptyStateExplainsTwoSteps() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }
        #expect(rig.state.isEmpty); #expect(rig.state.cards.isEmpty); #expect(rig.state.prompt == nil);
        #expect(!rig.state.showsAddButton)
        #expect(RecipeText.title == "Your font")
        #expect(RecipeText.subtitle == "Combine installed fonts into one font that every app can use.")
        #expect(RecipeText.mainTitle == "Main font")
        #expect(
            RecipeText.mainDescription == "The font you like for letters and numbers. It also sets the line spacing.")
        #expect(RecipeText.otherTitle == "Fonts for other languages")
        #expect(
            RecipeText.otherDescription == "Chinese, Japanese, Korean… They fill in whatever the main font can't draw.")
        #expect(RecipeText.chooseMain == "Choose main font…")
        rig.model.perform(.chooseMain); #expect(rig.model.pickRequest == PickRequest(languageID: "latin"))
    }
    @Test func emptyStateGoesAndComesBack() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let faces = try RecipeTestFaces.basic()
        rig.load([faces[0]], sample: "abc"); #expect(!rig.state.isEmpty); #expect(rig.state.showsAddButton)
        rig.model.edit { recipe in
            let text = recipe.sampleText; recipe = Recipe(); recipe.setSampleText(text)
        }
        #expect(rig.state.isEmpty); #expect(!rig.state.showsAddButton); #expect(rig.model.recipe.sampleText == "abc")
    }
    @Test func promptFollowsSampleAndFontCount() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let faces = try RecipeTestFaces.basic()
        rig.load([faces[0]], sample: "ab 漢字 あ")
        #expect(rig.state.prompt?.text == "Your text has Chinese and Japanese characters that Fixture A can't draw.")
        #expect(rig.state.prompt?.buttonTitle == "Choose a font for Chinese…")
        #expect(rig.state.prompt?.request == PickRequest(languageID: "chinese_s"))
        rig.model.edit { $0.setSampleText("abc") }; #expect(rig.state.prompt == nil)
        rig.model.edit { $0.setSampleText("ab あ") };
        #expect(rig.state.prompt?.buttonTitle == "Choose a font for Japanese…")
        rig.model.edit { $0.add(faces[1]) }; #expect(rig.state.prompt == nil)
        rig.model.perform(.remove(faces[1].key)); #expect(rig.state.prompt != nil)
    }
    @Test func cardsFollowRecipeOrder() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let f = try RecipeTestFaces.basic()
        rig.load(Array(f.prefix(3))); #expect(rig.state.cards.map(\.id) == Array(f.prefix(3)).map(\.key))
        rig.model.perform(.setWeight(f[1].key, 700)); rig.model.perform(.setSizePercent(f[1].key, 120))
        #expect(rig.state.cards.map(\.id) == Array(f.prefix(3)).map(\.key)); #expect(rig.state.cards[1].weight == 700);
        #expect(rig.state.cards[1].sizePercent == 120)
        rig.model.perform(.makeMain(f[2].key)); #expect(rig.state.cards.map(\.id) == [f[2].key, f[0].key, f[1].key])
        rig.model.perform(.remove(f[0].key)); #expect(rig.state.cards.map(\.id) == [f[2].key, f[1].key])
    }
    @Test func namesInOwnFaceWhenCovered() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; rig.load(try RecipeTestFaces.coveredNames())
        #expect(rig.state.cards[0].nativeName == nil); #expect(rig.state.cards[1].nativeName == "汉字体")
        #expect(rig.state.cards.allSatisfy { $0.nameInOwnFace }); #expect(rig.state.cards[1].nativeInOwnFace)
        rig.load([try RecipeTestFaces.basic()[0]])
        #expect(!rig.state.cards[0].nameInOwnFace)
    }
    @Test("CRIT-2 / CATALOG-7: missing cards stay visibly marked and repairable")
    func crit2Catalog7MissingCardsStayMarkedAndRepairable() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }
        let faces = try RecipeTestFaces.coveredNames()
        for restored in [false, true] {
            rig.load(faces)
            rig.model.edit { recipe in
                if restored {
                    recipe = RecipeDocument(recipe: recipe).makeRecipe(catalog: FaceCatalog([])).recipe
                } else {
                    _ = recipe.reconcile(with: FaceCatalog([]))
                }
            }
            #expect(rig.model.recipe.materials.allSatisfy { $0.availability == (restored ? .notFound : .fileGone) })
            #expect(rig.state.cards.map(\.id) == faces.map(\.key))
            #expect(rig.state.cards.allSatisfy { $0.unavailableLine == "Missing font — replace or remove it." })
            #expect(rig.state.cards.allSatisfy { !$0.nameInOwnFace && !$0.nativeInOwnFace })
            rig.model.perform(.pick(rig.state.cards[0].changeRequest))
            #expect(rig.model.pickRequest?.replaceKey == faces[0].key)
            rig.model.perform(.remove(faces[1].key))
            #expect(rig.model.recipe.keys == [faces[0].key])
            rig.model.edit { _ = $0.reconcile(with: FaceCatalog(faces)) }
            #expect(rig.state.cards[0].unavailableLine == nil)
        }
    }
    @Test func firstCardHasNoSizeOrWeight() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let f = try RecipeTestFaces.basic();
        rig.load(Array(f.prefix(2)))
        #expect(!rig.state.cards[0].showsAdjustments); #expect(rig.state.cards[1].showsAdjustments)
        #expect(rig.state.cards[1].sizePercent == 100); #expect(rig.state.cards[1].weight == nil)
        rig.model.perform(.setSizePercent(f[1].key, 5)); #expect(rig.state.cards[1].sizePercent == 10)
        rig.model.perform(.setSizePercent(f[1].key, 2000)); #expect(rig.state.cards[1].sizePercent == 1000)
    }
    @Test func rolesAndDrawsAreAlwaysCurrent() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let f = try RecipeTestFaces.basic();
        rig.load(Array(f.prefix(2)))
        #expect(rig.state.cards.map(\.role) == ["MAIN FONT", "FOR CHINESE"])
        #expect(
            rig.state.cards.map(\.draws) == [
                "Draws letters, numbers and punctuation. Sets the line spacing.",
                "Draws Chinese characters and CJK punctuation.",
            ])
        rig.model.edit {
            $0.add(f[3]); $0.add(f[2])
        }
        #expect(rig.state.cards[2].role == "ADDS NOTHING");
        #expect(rig.state.cards[2].draws == "Draws nothing — the fonts above already cover everything it has.")
        #expect(rig.state.cards[3].role == "FOR GREEK")
    }
    @Test func lineSpacingSentenceFollowsBase() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let f = try RecipeTestFaces.basic();
        rig.load(Array(f.prefix(2)))
        rig.model.edit { $0.setBase(f[1].key) }
        #expect(!rig.state.cards[0].draws.hasSuffix("Sets the line spacing."));
        #expect(rig.state.cards[1].draws.hasSuffix(" Sets the line spacing."))
        #expect(rig.state.cards.map(\.id) == [f[0].key, f[1].key])
        rig.model.edit { $0.setBase(nil) }; #expect(rig.state.cards[0].draws.hasSuffix(" Sets the line spacing."))
    }
    @Test func licenceLineOnlyForRestricted() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let f = try RecipeTestFaces.basic();
        rig.load([f[0], f[2]])
        #expect(rig.state.cards[0].licenceLine == nil)
        #expect(
            rig.state.cards[1].licenceLine
                == "Its licence restricts embedding — fine for your own use; check before sharing the result.")
    }
    @Test func styleChoiceKeepsAdjustments() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let a = try RecipeTestFaces.basic()[0]
        let regular = try RecipeTestFaces.make("regular.ttf", family: "Fake", chars: "漢")
        let bold = try RecipeTestFaces.make("bold.ttf", family: "Fake", chars: "漢", style: "Bold", weight: 700)
        let other = try RecipeTestFaces.make("other.ttf", family: "Other", chars: "漢", style: "Medium", weight: 500)
        rig.load([a, regular], catalog: [a, regular, bold, other])
        rig.model.edit { $0.setAdjustments(for: regular.key, weight: 600, scale: 1.1) }
        rig.model.perform(.chooseStyle(regular.key, bold))
        #expect(rig.model.recipe.keys == [a.key, bold.key]); #expect(rig.state.cards[1].weight == 600);
        #expect(rig.state.cards[1].sizePercent == 110)
        #expect(rig.state.cards[1].styles.map(\.style) == ["Regular", "Bold"]);
        #expect(rig.state.cards[1].face.style == "Bold")
    }
    @Test func sizeAndWeightSetTheAdjustment() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let f = try RecipeTestFaces.basic();
        rig.load(Array(f.prefix(2))); let key = f[1].key
        rig.model.perform(.setSizePercent(key, 120)); #expect(rig.model.recipe.materials[1].weight == nil);
        #expect(rig.model.recipe.materials[1].scale == 1.2)
        rig.model.perform(.setWeight(key, 700)); #expect(rig.model.recipe.materials[1].weight == 700);
        #expect(rig.model.recipe.materials[1].scale == 1.2)
        rig.model.perform(.setSizePercent(key, 100)); #expect(rig.model.recipe.materials[1].weight == 700);
        #expect(rig.model.recipe.materials[1].scale == nil)
        rig.model.perform(.setWeight(key, nil)); #expect(rig.model.recipe.materials[1].weight == nil);
        #expect(rig.model.recipe.materials[1].scale == nil)
    }
    @Test func menuActionsFollowPosition() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let f = try RecipeTestFaces.basic();
        rig.load(Array(f.prefix(3)))
        #expect(!rig.state.cards[0].canMakeMain && !rig.state.cards[0].canMoveUp && rig.state.cards[0].canMoveDown)
        #expect(rig.state.cards[1].canMakeMain && rig.state.cards[1].canMoveUp && rig.state.cards[1].canMoveDown)
        #expect(!rig.state.cards[2].canMoveDown)
        rig.model.perform(.makeMain(f[2].key)); #expect(rig.model.recipe.keys == [f[2].key, f[0].key, f[1].key])
        rig.model.perform(.moveDown(f[0].key)); #expect(rig.model.recipe.keys == [f[2].key, f[1].key, f[0].key])
        rig.model.perform(.moveUp(f[0].key)); #expect(rig.model.recipe.keys == [f[2].key, f[0].key, f[1].key])
        rig.model.perform(.remove(f[2].key)); #expect(rig.model.recipe.keys == [f[0].key, f[1].key])
    }
    @Test func changeAsksInTheCardsLanguage() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let f = try RecipeTestFaces.basic();
        rig.load([f[0], f[1], f[3]])
        #expect(
            rig.state.cards.map(\.changeRequest) == [
                .init(languageID: "latin", replaceKey: f[0].key), .init(languageID: "chinese_s", replaceKey: f[1].key),
                .init(languageID: "any", replaceKey: f[3].key),
            ])
    }
    @Test func addMenuOffersEveryLanguageThenAny() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }
        #expect(RecipeText.addMenuLanguages == Languages.all.filter { $0.id != .any });
        #expect(RecipeText.anyLanguage == "Any language…")
        #expect(EnglishText.languageLabel(.armenianGeorgian) == "Armenian & Georgian")
        for id in ["japanese", "any"] {
            rig.model.perform(.pick(.init(languageID: id))); #expect(rig.model.pickRequest?.languageID == id)
        }
    }
    @Test func lockedWhileBuilding() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let f = try RecipeTestFaces.basic();
        rig.load(Array(f.prefix(2)))
        let unlocked = rig.state, recipe = rig.model.recipe
        let actions: [RecipeAction] = [
            .chooseMain, .pick(.init(languageID: "any")), .chooseStyle(f[1].key, f[2]), .setWeight(f[1].key, 700),
            .setSizePercent(f[1].key, 120), .makeMain(f[1].key), .moveUp(f[1].key), .moveDown(f[0].key),
            .remove(f[0].key),
        ]
        #expect(RecipeAction.showAdvanced.isAllowedWhileBuilding);
        #expect(actions.allSatisfy { !$0.isAllowedWhileBuilding })
        rig.model.isBuilding = true
        for action in actions {
            rig.model.perform(action); #expect(rig.model.recipe == recipe); #expect(rig.model.pickRequest == nil)
        }
        #expect(rig.state.isLocked); #expect(rig.state.cards == unlocked.cards)
        rig.model.perform(.showAdvanced); #expect(rig.model.inspectorPresented)
    }
    @Test func shapingLinesFollowADR0008() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() };
        let a = try RecipeTestFaces.basic()[0], geeza = try RecipeTestFaces.geeza()
        rig.load([a, geeza], sample: "ا"); let card = rig.state.cards[1]
        #expect(rig.model.analysis.tallies[1][.arabic, default: 0] == 0); #expect(card.shapingProblems.count == 1)
        #expect(
            card.shapingProblems.first?.text
                == "Geeza Pro can't shape Arabic in your font: its Arabic shaping is Apple-only.")
        #expect(card.shapingProblems.first?.buttonTitle == "Choose a font for Arabic…")
        #expect(card.shapingProblems.first?.request == PickRequest(languageID: "arabic")); #expect(!card.appleOnlyNote)
        rig.model.edit {
            $0.setSampleText("abc"); $0.setPin(.arabic, to: geeza.key)
        }; #expect(rig.state.cards[1].shapingProblems.count == 1)
        let morx = try RecipeTestFaces.make(
            "M.ttf", family: "Morx Latin", chars: "abcdefgh",
            fields: ["aat": ["morx": true], "ot_scripts": ["gsub": []]])
        rig.load([morx]); #expect(rig.state.cards[0].appleOnlyNote); #expect(rig.state.cards[0].shapingProblems.isEmpty)
        rig.load([a]); #expect(!rig.state.cards[0].appleOnlyNote); #expect(rig.state.cards[0].shapingProblems.isEmpty)
        rig.load([a, try RecipeTestFaces.geeza(shapes: ["arabic"])], sample: "ا");
        #expect(rig.state.cards[1].shapingProblems.isEmpty)
    }
    @Test func dotsUseTheMixPalette() {
        #expect(MixPalette.colour(forMaterialAt: 4) == MixPalette.colour(forMaterialAt: 0))
        #expect(MixPalette.colour(forMaterialAt: 0) != MixPalette.colour(forMaterialAt: 1))
        #expect(
            RecipeText.dotAccessibilityLabel(index: 0, locale: Locale(identifier: "en_US"))
                == "Colour 1 in Colour by Font")
    }
    @Test("ENGINE-4: weight choice uses a real heavier face") func engine4WeightChoiceUsesARealHeavierFace() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let a = try RecipeTestFaces.basic()[0]
        let regular = try RecipeTestFaces.make("pf-r.ttf", family: "PingFang SC", chars: "漢")
        let medium = try RecipeTestFaces.make(
            "pf-m.ttf", family: "PingFang SC", chars: "漢", style: "Medium", weight: 500)
        let semibold = try RecipeTestFaces.make(
            "pf-s.ttf", family: "PingFang SC", chars: "漢", style: "Semibold", weight: 600)
        rig.load([a, regular], catalog: [a, regular, medium, semibold]); let previous = rig.model.recipe
        let swaps = rig.model.perform(.setWeight(regular.key, 600))
        #expect(swaps.count == 1); #expect(swaps.first?.to.key == semibold.key);
        #expect(rig.model.recipe.keys == [a.key, semibold.key])
        #expect(rig.model.recipe.materials[1].weight == 600);
        #expect(rig.model.perform(.setWeight(semibold.key, 600)).isEmpty)
        rig.model.edit { $0 = previous }; #expect(rig.model.recipe.keys == [a.key, regular.key])
    }
    @Test func staleCardActionsDoNothing() throws {
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let f = try RecipeTestFaces.basic(); rig.load([f[0]])
        let before = rig.model.recipe
        for action in [
            RecipeAction.remove(f[1].key), .setWeight(f[1].key, 600), .setSizePercent(f[1].key, 120),
            .chooseStyle(f[1].key, f[2]), .makeMain(f[1].key), .pick(.init(languageID: "any", replaceKey: f[1].key)),
        ] {
            rig.model.perform(action); #expect(rig.model.recipe == before); #expect(rig.model.pickRequest == nil)
        }
    }
}
