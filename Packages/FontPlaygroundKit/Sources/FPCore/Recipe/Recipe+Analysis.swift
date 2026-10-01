import Foundation

extension Recipe {
    public func analyze() -> RecipeAnalysis {
        let mix = mix(), plan = mix.plan()
        let tallies = plan.tallies()
        let estimate = materials.isEmpty ? 0 : GlyphBudget.estimate(faces: materials.map(\.face), plan: plan)
        let warning: GlyphWarning? =
            estimate > GlyphBudget.maxGlyphs
            ? .overLimit(estimate: estimate)
            : estimate > GlyphBudget.warnAt ? .nearLimit : nil
        var problems: [RecipeProblem] = []
        if materials.isEmpty {
            problems = [.empty]
        } else {
            for (index, material) in materials.enumerated() where !material.isAvailable {
                problems.append(.materialUnavailable(index: index, material.availability))
            }
            problems += SpecValidation.problems(forgeSpec(), faces: materials.map(\.face))
            // ENGINE-2 / S7: inspect explicit rules and raw coverage. A plan already excludes unshaped scalars.
            for group in ScriptGroup.allCases where group.needsShaping {
                guard let index = mix.rules[group], materials.indices.contains(index), materials[index].isAvailable
                else { continue }
                let face = materials[index].face
                if let shapes = face.shapesGroups, !shapes.contains(group),
                    !face.coverage.intersection(ScriptGroup.codepoints(of: group)).isEmpty
                {
                    problems.append(.cannotShape(index: index, group: group))
                }
            }
            if estimate > GlyphBudget.maxGlyphs { problems.append(.glyphLimit(estimate: estimate)) }
        }
        return RecipeAnalysis(
            mix: mix, plan: plan, tallies: tallies, glyphEstimate: estimate, glyphWarning: warning,
            problems: problems, missingSampleCharacters: mix.missingCharacters(in: sampleText))
    }
}
