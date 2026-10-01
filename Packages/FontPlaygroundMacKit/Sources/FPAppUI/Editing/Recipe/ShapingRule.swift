import FPCore

enum ShapingRule {
    static func canShape(_ face: FaceRecord, language: Language) -> Bool {
        guard let shapes = face.shapesGroups else { return true }
        return language.groups.filter(\.needsShaping).allSatisfy { shapes.contains($0) }
    }
    static func problems(for face: FaceRecord, index: Int, recipe: Recipe, analysis: RecipeAnalysis) -> [ShapingProblem]
    {
        guard let shapes = face.shapesGroups else { return [] }
        let visible = TextUtil.visibleScalars(in: recipe.sampleText)
        return ScriptGroup.allCases.compactMap { group in
            guard group.needsShaping, !shapes.contains(group), let id = group.language,
                analysis.problems.contains(.cannotShape(index: index, group: group))
                    || visible.contains(where: { ScriptGroup.of($0) == group && face.unshaped.contains($0.value) })
            else { return nil }
            let language = Languages.language(id)
            return .init(
                group: group, language: language,
                text: RecipeText.shapingProblem(family: face.family, language: language),
                buttonTitle: RecipeText.promptButtonTitle(language))
        }
    }
}
