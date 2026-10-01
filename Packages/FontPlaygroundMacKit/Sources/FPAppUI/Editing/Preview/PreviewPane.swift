import FPCore
import SwiftUI

public struct PreviewPane: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }
    public var body: some View {
        let configuration = model.previewConfiguration
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    heading; controls
                }
                VStack(alignment: .leading, spacing: 8) {
                    heading
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            colourToggle; Spacer(); samples
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            colourToggle; samples
                        }
                    }
                    sizeControls
                }
            }
            if let trial = model.trial {
                Text(trial.banner).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(
                    .tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            // Above the editor, not over it: wrapped text at half-screen width ran under an overlaid badge.
            if case .built(let built, _) = configuration.mode {
                HStack {
                    Spacer()
                    Label(PreviewText.builtBadge, systemImage: "checkmark.seal").font(.caption).padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule()).help(
                            Text(PreviewText.builtHelp(built.displayName))
                        )
                        .accessibilityLabel(Text(PreviewText.builtBadgeAccessibilityLabel))
                        .allowsHitTesting(false)
                }
            }
            PreviewTextEditor(model: model)
                .overlay(alignment: .topLeading) {
                    if model.recipe.sampleText.isEmpty {
                        Text(PreviewText.placeholder).foregroundStyle(.tertiary).padding(14).allowsHitTesting(false)
                    }
                }
            if let note = PreviewText.missingNote(configuration, text: model.recipe.sampleText) {
                MissingNoteStrip(note: note, disabled: model.isBuilding) { model.openPicker(note.request) }
            }
        }.padding(12)
    }
    private var heading: some View {
        HStack {
            Text(PreviewText.title).accessibilityAddTraits(.isHeader).font(.headline);
            Text(PreviewText.hint).foregroundStyle(.secondary).lineLimit(1).layoutPriority(-1); Spacer(minLength: 0)
        }
    }
    private var controls: some View {
        HStack(spacing: 8) {
            colourToggle; sizeControls; samples
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var colourToggle: some View {
        Toggle(PreviewText.colourByFont, isOn: $model.colourByFont).toggleStyle(.button).help(
            Text(PreviewText.colourHelp))
    }
    private var sizeControls: some View {
        HStack(spacing: 8) {
            Text(PreviewText.size)
            Slider(
                value: Binding(
                    get: { Double(model.previewPointSize) }, set: { model.previewPointSize = Int($0.rounded()) }),
                in: 10...96
            )
            .frame(width: 140).accessibilityLabel(Text(PreviewText.sizeAccessibilityLabel)).accessibilityValue(
                Text(PreviewText.sizeAccessibilityValue(model.previewPointSize)))
            Text(PreviewText.sizeText(model.previewPointSize)).monospacedDigit().frame(width: 42)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var samples: some View {
        let label = PreviewText.sampleSelectionLabel(model.recipe.sampleText)
        return Menu(label) {
            ForEach(Samples.presets, id: \.id) { preset in
                Button(ModelText.samplePresetLabel(preset.id)) { model.applySample(id: preset.id) }
            }
        }.fixedSize(horizontal: true, vertical: false).help(Text(PreviewText.sampleHelp))
            .accessibilityLabel(Text(PreviewText.sampleText)).accessibilityValue(Text(label))
    }
}

struct MissingNoteStrip: View {
    let note: MissingNote
    let disabled: Bool
    let action: () -> Void
    var body: some View {
        HStack(alignment: .top) {
            Text(note.text).frame(maxWidth: .infinity, alignment: .leading);
            // WP-701 finding G: at half-screen width the button was squeezed to "Add a font for Chines…";
            // the note wraps instead.
            Button(note.buttonTitle, action: action).buttonStyle(.bordered).disabled(disabled).fixedSize()
        }
        .padding(10).background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}
