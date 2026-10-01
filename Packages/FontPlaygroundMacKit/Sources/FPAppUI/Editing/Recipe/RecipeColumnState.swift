import FPCore

struct RecipeColumnState: Equatable {
    var isEmpty: Bool
    var cards: [FontCardState]
    var prompt: PromptState?
    var isLocked: Bool
    var showsAddButton: Bool { !isEmpty }

    static func make(recipe: Recipe, catalog: [FaceRecord], isBuilding: Bool) -> Self {
        let analysis = recipe.analyze()
        let cards = recipe.materials.enumerated().map { index, material in
            let face = material.face, tally = analysis.tallies[index]
            let problems = ShapingRule.problems(for: face, index: index, recipe: recipe, analysis: analysis)
            let native = face.localNames.first
            return FontCardState(
                id: face.key, index: index, count: recipe.materials.count, face: face,
                role: index == 0 ? RecipeText.mainRole : ModelText.roleTitle(Languages.roleTitle(tally)),
                draws: ModelText.draws(Languages.namedGroups(tally))
                    + (index == recipe.baseIndex ? " " + RecipeText.lineSpacing : ""),
                nameInOwnFace: material.isAvailable && canDraw(face.family, face: face), nativeName: native,
                nativeInOwnFace: material.isAvailable && (native.map { canDraw($0, face: face) } ?? false),
                styles: RecipeText.familyStyles(face, catalog), weight: material.weight,
                sizePercent: RecipeText.scalePercent(material.scale),
                showsAdjustments: index > 0, licenceLine: face.embedding == .restricted ? RecipeText.licence : nil,
                unavailableLine: material.isAvailable ? nil : RecipeText.missingFont, shapingProblems: problems,
                appleOnlyNote: face.aat.morx && face.otScripts.gsub.isEmpty && problems.isEmpty,
                canMakeMain: index > 0, canMoveUp: index > 0, canMoveDown: index < recipe.materials.count - 1,
                changeRequest: PickRequest(
                    languageID: index == 0 ? "latin" : RecipeText.tallyLanguage(tally), replaceKey: face.key),
                dotColourIndex: index)
        }
        var prompt: PromptState?
        if recipe.materials.count == 1 {
            let languages = Languages.languagesForMissing(analysis.missingSampleCharacters)
            if let language = languages.first, let main = recipe.main {
                prompt = .init(
                    text: RecipeText.promptText(languages, family: main.family),
                    buttonTitle: RecipeText.promptButtonTitle(language),
                    request: PickRequest(languageID: language.id.rawValue))
            }
        }
        return .init(isEmpty: cards.isEmpty, cards: cards, prompt: prompt, isLocked: isBuilding)
    }
    private static func canDraw(_ text: String, face: FaceRecord) -> Bool {
        TextUtil.visibleScalars(in: text).allSatisfy { face.coverage.contains($0.value) }
    }
}
struct FontCardState: Identifiable, Equatable {
    var id: FaceKey
    var index: Int, count: Int
    var face: FaceRecord
    var role: String, draws: String
    var nameInOwnFace: Bool
    var nativeName: String?
    var nativeInOwnFace: Bool
    var styles: [FaceRecord]
    var weight: Int?
    var sizePercent: Int
    var showsAdjustments: Bool
    var licenceLine: String?
    var unavailableLine: String?
    var shapingProblems: [ShapingProblem]
    var appleOnlyNote: Bool
    var canMakeMain: Bool, canMoveUp: Bool, canMoveDown: Bool
    var changeRequest: PickRequest
    var dotColourIndex: Int
}
struct PromptState: Equatable { var text: String; var buttonTitle: String; var request: PickRequest }
struct ShapingProblem: Equatable {
    var group: ScriptGroup
    var language: Language
    var text: String
    var buttonTitle: String
    var request: PickRequest { .init(languageID: language.id.rawValue) }
}
enum RecipeAction: Equatable {
    case chooseMain
    case pick(PickRequest)
    case chooseStyle(FaceKey, FaceRecord)
    case setWeight(FaceKey, Int?)
    case setSizePercent(FaceKey, Int)
    case makeMain(FaceKey), moveUp(FaceKey), moveDown(FaceKey), remove(FaceKey)
    case showAdvanced
    var isAllowedWhileBuilding: Bool { self == .showAdvanced }
}
