import FPCore
import Foundation

public struct AdvancedModel {
    public struct Choice: Equatable {
        public var title: String
        public var key: FaceKey?
        public var isDisabled: Bool
    }
    public struct ScriptRow: Equatable, Identifiable {
        public var id: ScriptGroup
        public var label: String
        public var isCovered: Bool
        public var choices: [Choice]
        public var selectedIndex: Int
        public var countsText: String
        public var drawnByText: String
    }
    public var rows: [ScriptRow]
    public var lineSpacingChoices: [String]
    public var lineSpacingIndex: Int
    public var weightChoices: [WeightChoice]
    public var weightIndex: Int
    public var sizePercent: Int
    public var reportText: String
    public var controlsEnabled: Bool
    public var lineSpacingEnabled: Bool
    private let keys: [FaceKey]

    public init(
        recipe: Recipe, showAll: Bool, isLocked: Bool, lastReport: ForgeReport?, lastErrorDetail: String?,
        locale: Locale = .current
    ) {
        keys = recipe.keys
        let counts = Dictionary(uniqueKeysWithValues: recipe.materials.map { ($0.key, RuleResolver.counts(for: $0)) })
        let names = Self.shortNames(recipe.materials.map(\.face))
        let display = Dictionary(uniqueKeysWithValues: recipe.materials.map { ($0.key, $0.face.displayName) })
        let rules = recipe.scriptRules()
        rows = ScriptGroup.allCases.compactMap { group in
            let label = ModelText.groupLabel(group)
            var ranked = recipe.materials.indices.filter { (counts[recipe.keys[$0]]?[group] ?? 0) > 0 }
            guard !ranked.isEmpty else {
                return showAll
                    ? ScriptRow(
                        id: group, label: label, isCovered: false, choices: [], selectedIndex: 0,
                        countsText: AdvancedText.noCount, drawnByText: AdvancedText.nobody)
                    : nil
            }
            ranked.sort { left, right in
                let a = counts[recipe.keys[left]]?[group] ?? 0, b = counts[recipe.keys[right]]?[group] ?? 0
                return a == b ? left < right : a > b
            }
            if let supplier = rules[group], let position = ranked.firstIndex(of: supplier) {
                ranked.remove(at: position); ranked.insert(supplier, at: 0)
            }
            let auto = RuleResolver.smartSupplier(group, counts: counts, order: recipe.keys)
            let choices =
                [Choice(title: AdvancedText.auto(auto.flatMap { display[$0] } ?? "?"), key: nil, isDisabled: false)]
                + recipe.materials.map { material in
                    // ADR-0008: the UI and the intent both refuse an Apple-only shaping choice.
                    let disabled = group.needsShaping && !material.face.canShape(group)
                    let name = material.face.displayName
                    return Choice(
                        title: disabled ? AdvancedText.cannotShape(name, group: label) : name,
                        key: material.key, isDisabled: disabled)
                }
            let selected = recipe.pins[group].flatMap { recipe.index(of: $0) }.map { $0 + 1 } ?? 0
            let text = ranked.map { index in
                let key = recipe.keys[index], count = counts[key]?[group] ?? 0
                return "\(names[key] ?? "?") \(count.formatted(.number.locale(locale)))"
            }.joined(separator: " · ")
            return ScriptRow(
                id: group, label: label, isCovered: true, choices: choices, selectedIndex: selected,
                countsText: text, drawnByText: choices[selected].title)
        }
        lineSpacingChoices = [AdvancedText.mainFont] + recipe.materials.map { $0.face.displayName }
        lineSpacingIndex = recipe.baseKey.flatMap { recipe.index(of: $0) }.map { $0 + 1 } ?? 0
        weightChoices = WeightChoice.standard
        if !weightChoices.contains(where: { $0.weight == recipe.defaultWeight }), let weight = recipe.defaultWeight {
            weightChoices.append(.init(weight: weight, title: weight.formatted(.number.locale(locale))))
        }
        weightIndex = weightChoices.firstIndex { $0.weight == recipe.defaultWeight } ?? 0
        sizePercent = Int(min(1000, max(10, (recipe.defaultScale * 100).rounded())))
        reportText = lastReport.map { ReportText.render($0) } ?? lastErrorDetail ?? AdvancedText.noBuild
        controlsEnabled = !isLocked
        lineSpacingEnabled = !isLocked && !recipe.materials.isEmpty
    }

    public static func shortNames(_ faces: [FaceRecord]) -> [FaceKey: String] {
        let families = Dictionary(grouping: faces, by: \.family)
        return Dictionary(
            uniqueKeysWithValues: faces.map { face in
                (face.key, families[face.family]?.count == 1 ? face.family : face.displayName)
            })
    }
    public static func weightSwapNotes(_ swaps: [WeightSwap]) -> [String] { swaps.map(ModelText.weightSwap) }

    public func pin(_ group: ScriptGroup, choiceIndex: Int) -> ((inout Recipe) -> Void)? {
        guard controlsEnabled, let row = rows.first(where: { $0.id == group }),
            row.choices.indices.contains(choiceIndex), !row.choices[choiceIndex].isDisabled
        else { return nil }
        let key = row.choices[choiceIndex].key
        return { $0.setPin(group, to: key) }
    }
    public func lineSpacing(index: Int) -> (inout Recipe) -> Void {
        guard lineSpacingEnabled, lineSpacingChoices.indices.contains(index) else { return { _ in } }
        let key = index == 0 ? nil : keys[index - 1]
        return { $0.setBase(key) }
    }
    public func defaults(weightIndex: Int?, sizePercent: Int?) -> (inout Recipe) -> Void {
        guard controlsEnabled else { return { _ in } }
        let choice = weightIndex.flatMap { weightChoices.indices.contains($0) ? weightChoices[$0] : nil }
        return { recipe in
            recipe.setDefaults(
                weight: choice.map(\.weight) ?? recipe.defaultWeight,
                scale: sizePercent.map { Double(min(1000, max(10, $0))) / 100 } ?? recipe.defaultScale)
        }
    }
}

@MainActor public enum AdvancedIntents {
    public static func state(_ model: AppModel) -> AdvancedModel {
        AdvancedModel(
            recipe: model.recipe, showAll: model.settings.showAllScriptGroups, isLocked: model.isBuilding,
            lastReport: model.build.lastReport, lastErrorDetail: model.build.lastErrorDetail)
    }
    public static func pin(_ model: AppModel, group: ScriptGroup, choiceIndex: Int) {
        if let change = state(model).pin(group, choiceIndex: choiceIndex) { model.edit(change) }
    }
    public static func lineSpacing(_ model: AppModel, index: Int) { model.edit(state(model).lineSpacing(index: index)) }
    @discardableResult public static func applyDefaults(
        _ model: AppModel, weightIndex: Int?, sizePercent: Int?
    ) -> [WeightSwap] {
        let change = state(model).defaults(weightIndex: weightIndex, sizePercent: sizePercent)
        let catalog = FaceCatalog(model.catalogFaces)
        var swaps: [WeightSwap] = []
        model.edit { recipe in
            let previousWeight = recipe.defaultWeight
            change(&recipe)
            if recipe.defaultWeight != previousWeight { swaps = recipe.applyRealWeights(in: catalog) }
        }
        return swaps
    }
}
