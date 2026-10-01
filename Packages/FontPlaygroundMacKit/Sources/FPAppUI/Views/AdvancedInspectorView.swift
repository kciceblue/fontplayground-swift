import FPCore
import SwiftUI

public struct AdvancedInspectorView: View {
    let model: AppModel
    @State private var swaps: [WeightSwap] = []
    @State private var previousRecipe: Recipe?
    @State private var recipeWithSwaps: Recipe?
    @State private var draftSize: Int
    @State private var sizeFieldIdentity = 0
    @FocusState private var sizeFocused: Bool
    public init(model: AppModel) {
        self.model = model
        _draftSize = State(initialValue: AdvancedIntents.state(model).sizePercent)
    }
    public var body: some View {
        let state = AdvancedIntents.state(model)
        Form {
            Section(AdvancedText.who) {
                ForEach(state.rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        if row.isCovered {
                            Picker(
                                row.label,
                                selection: Binding(
                                    get: { row.selectedIndex },
                                    set: { AdvancedIntents.pin(model, group: row.id, choiceIndex: $0) })
                            ) {
                                ForEach(Array(row.choices.enumerated()), id: \.offset) { index, choice in
                                    Text(choice.title).tag(index).selectionDisabled(choice.isDisabled)
                                }
                            }.pickerStyle(.menu).accessibilityLabel(row.label).accessibilityValue(row.drawnByText).help(
                                AdvancedText.drawnByHelp
                            ).disabled(!state.controlsEnabled)
                        } else {
                            LabeledContent(row.label, value: row.drawnByText)
                        }
                        Text(row.countsText).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Toggle(
                    AdvancedText.showAll(ScriptGroup.allCases.count),
                    isOn: Binding(
                        get: { model.settings.showAllScriptGroups }, set: { model.settings.showAllScriptGroups = $0 })
                ).help(AdvancedText.showAllHelp)
            }
            Section(AdvancedText.lineSpacingSection) {
                Picker(
                    AdvancedText.lineSpacing,
                    selection: Binding(
                        get: { state.lineSpacingIndex }, set: { AdvancedIntents.lineSpacing(model, index: $0) })
                ) {
                    ForEach(Array(state.lineSpacingChoices.enumerated()), id: \.offset) { index, title in
                        Text(title).tag(index)
                    }
                }.pickerStyle(.menu).help(AdvancedText.lineSpacingHelp).disabled(!state.lineSpacingEnabled)
            }
            Section {
                Picker(
                    AdvancedText.defaultBoldness,
                    selection: Binding(
                        get: { state.weightIndex }, set: { applyDefaults(weightIndex: $0, sizePercent: nil) })
                ) {
                    ForEach(Array(state.weightChoices.enumerated()), id: \.offset) { index, choice in
                        Text(choice.title).tag(index)
                    }
                }.pickerStyle(.menu).help(AdvancedText.defaultBoldnessHelp).disabled(!state.controlsEnabled)
                HStack {
                    Text(AdvancedText.defaultSize)
                    Spacer()
                    TextField(AdvancedText.defaultSize, value: $draftSize, format: .number)
                        .labelsHidden()
                        .frame(width: 52).id(sizeFieldIdentity).focused($sizeFocused)
                        .onSubmit { commitSize() }
                        .onChange(of: sizeFocused) { _, focused in if !focused { commitSize() } }
                        .accessibilityValue(AdvancedText.percent(state.sizePercent))
                    Text(AdvancedText.percentSuffix)
                    Stepper(
                        AdvancedText.defaultSize,
                        value: Binding(
                            get: { state.sizePercent }, set: { applyDefaults(weightIndex: nil, sizePercent: $0) }),
                        in: 10...1000
                    ).labelsHidden().accessibilityValue(AdvancedText.percent(state.sizePercent))
                }.help(AdvancedText.defaultSizeHelp).disabled(!state.controlsEnabled)
                ForEach(Array(AdvancedModel.weightSwapNotes(swaps).enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline) {
                        Text(note).font(.callout).foregroundStyle(.secondary)
                        Button(AdvancedText.undo) { undoDefaults() }.buttonStyle(.link).disabled(!state.controlsEnabled)
                    }
                }
            } header: {
                Text(AdvancedText.defaults).accessibilityAddTraits(.isHeader)
            } footer: {
                Text(AdvancedText.defaultsNote)
            }
            Section(AdvancedText.lastBuild) {
                ScrollView {
                    Text(verbatim: state.reportText).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 240)
            }
        }.formStyle(.grouped)
            .onChange(of: state.sizePercent) { _, percent in draftSize = percent }
            .onChange(of: model.recipe) { _, recipe in
                if recipe != recipeWithSwaps { swaps = []; previousRecipe = nil; recipeWithSwaps = nil }
            }
    }
    private func applyDefaults(weightIndex: Int?, sizePercent: Int?) {
        let previous = model.recipe
        let result = AdvancedIntents.applyDefaults(model, weightIndex: weightIndex, sizePercent: sizePercent)
        if !result.isEmpty { previousRecipe = previous; recipeWithSwaps = model.recipe; swaps = result }
    }
    private func commitSize() {
        applyDefaults(weightIndex: nil, sizePercent: min(1000, max(10, draftSize)))
        draftSize = AdvancedIntents.state(model).sizePercent
        // Restore the committed number after invalid text, without rebuilding the inspector.
        sizeFieldIdentity += 1
    }
    private func undoDefaults() {
        guard let previousRecipe else { return }
        model.edit { $0 = previousRecipe }; swaps = []; self.previousRecipe = nil; recipeWithSwaps = nil
    }
}
