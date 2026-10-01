import FPCore
import SwiftUI

@MainActor struct RecipeColumn: View {
    let model: AppModel
    @State private var swaps: [WeightSwap] = []
    @State private var beforeWeightChange: Recipe?
    @State private var recipeWithSwaps: Recipe?
    init(model: AppModel) { self.model = model }
    var body: some View {
        let state = RecipeColumnState.make(
            recipe: model.recipe, catalog: model.catalogFaces, isBuilding: model.isBuilding)
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(RecipeText.title).font(.title3.weight(.semibold))
                    if state.isEmpty { emptyState.disabled(state.isLocked) }
                    ForEach(state.cards) { card in
                        VStack(alignment: .leading, spacing: 5) {
                            FontCardView(
                                state: card, renderer: model.renderer, colourByFont: model.colourByFont,
                                isLocked: state.isLocked, onAction: perform)
                            ForEach(Array(swaps.filter { $0.to.key == card.id }.enumerated()), id: \.offset) {
                                _, swap in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(ModelText.weightSwap(swap)).font(.callout).foregroundStyle(.secondary)
                                    Button(RecipeText.undo) { undoWeight() }.buttonStyle(.link).disabled(state.isLocked)
                                }
                            }
                        }
                    }
                    if let prompt = state.prompt {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(prompt.text).fixedSize(horizontal: false, vertical: true)
                                Button(prompt.buttonTitle) { perform(.pick(prompt.request)) }.buttonStyle(
                                    .borderedProminent)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.backgroundStyle(.tint.opacity(0.12)).disabled(state.isLocked)
                    }
                    if state.showsAddButton {
                        Menu {
                            ForEach(RecipeText.addMenuLanguages, id: \.id) { language in
                                Button(ModelText.languageLabel(language.id)) {
                                    perform(.pick(.init(languageID: language.id.rawValue)))
                                }
                            }
                            Divider()
                            Button(RecipeText.anyLanguage) { perform(.pick(.init(languageID: "any"))) }
                        } label: {
                            Label(RecipeText.add, systemImage: "plus")
                        }
                        .menuStyle(.button).buttonStyle(.bordered).disabled(state.isLocked)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button(RecipeText.advanced) { perform(.showAdvanced) }.buttonStyle(.link)
                Text(RecipeText.advancedHint).font(.caption).foregroundStyle(.secondary)
            }.padding([.horizontal, .bottom], 12)
        }
        .onChange(of: model.recipe) { _, recipe in
            if recipe != recipeWithSwaps { swaps = []; beforeWeightChange = nil; recipeWithSwaps = nil }
        }
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(RecipeText.subtitle).foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        badge(1, filled: true); Text(RecipeText.mainTitle).font(.headline)
                    }
                    Text(RecipeText.mainDescription).fixedSize(horizontal: false, vertical: true)
                    Button(RecipeText.chooseMain) { perform(.chooseMain) }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        badge(2, filled: false); Text(RecipeText.otherTitle).font(.headline)
                    }
                    Text(RecipeText.otherDescription).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func badge(_ value: Int, filled: Bool) -> some View {
        Text(value.formatted(.number)).font(.caption.weight(.semibold)).foregroundStyle(
            filled ? Color.white : Color.secondary
        )
        .frame(width: 22, height: 22).background(Circle().fill(filled ? Color.accentColor : .clear))
        .overlay(Circle().stroke(filled ? Color.clear : Color(nsColor: MixPalette.cardStroke), lineWidth: 1))
        .accessibilityHidden(true)
    }
    private func perform(_ action: RecipeAction) {
        let previous = model.recipe
        let result = model.perform(action)
        if !result.isEmpty { beforeWeightChange = previous; recipeWithSwaps = model.recipe; swaps = result }
    }
    private func undoWeight() {
        guard let previous = beforeWeightChange else { return }
        model.edit { $0 = previous }; swaps = []; beforeWeightChange = nil; recipeWithSwaps = nil
    }
}
