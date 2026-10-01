import FPCore
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct ModelTextTests {
    @Test func englishMatchesTheSourceText() {
        var a = ShellFaces.make("One", path: "/one.ttf", text: "abc"),
            b = ShellFaces.make("Two", path: "/two.ttf", text: "漢")
        a.aat.morx = true; b.weightClass = 700
        var recipe = Recipe(); recipe.add(a); recipe.add(b)
        let problems: [RecipeProblem] = [
            .empty, .materialUnavailable(index: 0, .notFound), .materialUnavailable(index: 1, .fileGone),
            .baseOutOfRange, .unsupported(index: 0, reason: "engine reason"), .unsupported(index: 1, reason: nil),
            .familyNameEmpty, .styleNameEmpty, .familyNameStartsWithDot, .familyNameHasControlCharacter,
            .styleNameHasControlCharacter, .ruleOutOfRange(.han), .scaleOutOfRange(index: 0, scale: 0.05),
            .scaleTooLarge(index: 1, scale: 9, baseUPM: 2048), .weightOutOfRange(index: 0, weight: 1001),
            .cannotShape(index: 0, group: .arabic), .cannotShape(index: 1, group: .indic),
            .glyphLimit(estimate: 1234567),
        ]
        for p in problems { #expect(ModelText.problem(p, in: recipe) == EnglishText.problem(p, in: recipe)) }
        for warning: GlyphWarning in [.nearLimit, .overLimit(estimate: 7654321)] {
            #expect(ModelText.glyphWarning(warning) == EnglishText.glyphWarning(warning))
        }
        var report = LoadReport(); #expect(ModelText.unresolvedSummary(report) == EnglishText.unresolvedSummary(report))
        for face in [a, b] {
            report.unresolved.append(
                PortableFaceIdentity(
                    postscriptName: face.postscriptName, family: face.family, style: face.style, path: face.path,
                    index: face.index))
            #expect(ModelText.unresolvedSummary(report) == EnglishText.unresolvedSummary(report))
        }
        #expect(
            ModelText.replacementOffer(missing: "SimSun", replacement: "Songti SC")
                == EnglishText.replacementOffer(missing: "SimSun", replacement: "Songti SC"))
        for group in ScriptGroup.allCases {
            #expect(ModelText.groupLabel(group) == EnglishText.groupLabel(group))
            #expect(ModelText.groupPhrase(group) == EnglishText.groupPhrase(group))
        }
        for language in Languages.all {
            #expect(ModelText.languageLabel(language.id) == EnglishText.languageLabel(language.id))
            #expect(ModelText.languageShortLabel(language.id) == EnglishText.languageShortLabel(language.id))
        }
        for preset in Samples.presets {
            #expect(ModelText.samplePresetLabel(preset.id) == EnglishText.samplePresetLabel(preset.id))
        }
        for (from, to, weight) in [(a, b, 700), (b, a, 400)] {
            let swap = WeightSwap(index: 1, from: from, to: to, requestedWeight: weight, remainingSyntheticBold: 0)
            #expect(ModelText.weightSwap(swap) == EnglishText.weightSwap(swap))
        }
        for note: WeightNote in [.syntheticBold(index: 0, delta: 300), .cannotMakeLighter(index: 1)] {
            #expect(ModelText.weightNote(note) == EnglishText.weightNote(note))
        }
        for issue: CatalogIssue in [
            .noAccess(folder: "/test"), .folderMissing(folder: "/test"),
            .folderUnreadable(folder: "/test", message: "reason"),
            .unreadable(path: "/font", code: "bad", message: "detail"), .skipped(path: "/font", reason: .appleDouble),
            .duplicate(kept: a.key, dropped: b.key, postscriptName: "PS"), .disabledUnlocated(postscriptName: "PS"),
        ] { #expect(ModelText.catalogIssue(issue) == issue.englishText) }
        for groups: [ScriptGroup] in [
            [], [.latin], [.han], [.latin, .han, .kana, .hangul, .arabic], [.han, .kana, .hangul, .arabic],
        ] { #expect(ModelText.draws(groups) == EnglishText.draws(groups)) }
        for role: RoleTitle in [.addsNothing, .fillsInTheRest, .forLanguages([.chineseSimplified, .japanese])] {
            #expect(ModelText.roleTitle(role) == EnglishText.roleTitle(role))
        }
        for limit in [-2, 0, 1, 2, 5] {
            #expect(
                ModelText.joinLabels([.chineseSimplified, .chineseTraditional, .japanese, .korean], limit: limit)
                    == EnglishText.joinLabels(
                        [.chineseSimplified, .chineseTraditional, .japanese, .korean], limit: limit))
        }
    }
    @Test func weightListsAgree() {
        #expect(WeightChoice.standard.map(\.weight) == RecipeText.weightChoices.map(\.0))
        #expect(WeightChoice.standard.map(\.title) == RecipeText.weightChoices.map(\.1))
    }
}
