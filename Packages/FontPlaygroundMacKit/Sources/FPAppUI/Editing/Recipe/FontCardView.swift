import AppKit
import CoreText
import FPCore
import FPMacServices
import SwiftUI

@MainActor struct FontCardView: View {
    let state: FontCardState
    let renderer: any FontRendering
    let colourByFont: Bool
    let isLocked: Bool
    let onAction: (RecipeAction) -> Void
    @State private var draftSize: Int
    @State private var sizeFieldIdentity = 0
    @State private var fontFailures = RecipeLabelFontFailures()
    @FocusState private var sizeFocused: Bool

    init(
        state: FontCardState, renderer: any FontRendering, colourByFont: Bool, isLocked: Bool,
        onAction: @escaping (RecipeAction) -> Void
    ) {
        self.state = state; self.renderer = renderer; self.colourByFont = colourByFont; self.isLocked = isLocked
        self.onAction = onAction; _draftSize = State(initialValue: state.sizePercent)
    }
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    dot
                    Text(state.role).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(RecipeText.change) { onAction(.pick(state.changeRequest)) }.buttonStyle(.link).help(
                        RecipeText.changeHelp)
                    Menu {
                        actions
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel(RecipeText.moreActionsAccessibilityLabel(family: state.face.family))
                    }
                    .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden)
                    .accessibilityLabel(RecipeText.moreActionsAccessibilityLabel(family: state.face.family))
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    faceName(state.face.family, size: 17, own: state.nameInOwnFace)
                    if let native = state.nativeName {
                        faceName(native, size: 12, own: state.nativeInOwnFace).foregroundStyle(.secondary)
                    }
                }
                if let message = state.unavailableLine {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent(RecipeText.style) {
                    Picker(
                        RecipeText.style,
                        selection: Binding(
                            get: { state.id },
                            set: { key in
                                if let face = state.styles.first(where: { $0.key == key }) {
                                    onAction(.chooseStyle(state.id, face))
                                }
                            })
                    ) {
                        ForEach(state.styles, id: \.key) { face in Text(face.style).tag(face.key).help(face.displayName)
                        }
                    }.pickerStyle(.menu).labelsHidden().help(RecipeText.styleHelp)
                }
                if state.showsAdjustments { adjustments }
                Text(state.draws).font(.callout).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
                if let licence = state.licenceLine {
                    Text(licence).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(state.shapingProblems, id: \.group) { problem in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(problem.text, systemImage: "exclamationmark.triangle").font(.callout).fixedSize(
                            horizontal: false, vertical: true)
                        Button(problem.buttonTitle) { onAction(.pick(problem.request)) }.buttonStyle(.link)
                    }
                }
                if state.appleOnlyNote {
                    Text(RecipeText.appleOnly).font(.callout).foregroundStyle(.secondary).fixedSize(
                        horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu { actions }
        .disabled(isLocked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            RecipeText.cardAccessibilityLabel(role: state.role, family: state.face.family, style: state.face.style)
        )
        .accessibilityValue(state.draws)
        .onChange(of: state.sizePercent) { _, value in draftSize = value }
    }
    private var dot: some View {
        let colour = Color(nsColor: MixPalette.colour(forMaterialAt: state.dotColourIndex))
        return Circle().fill(colourByFont ? colour : .clear).overlay(
            Circle().stroke(Color(nsColor: MixPalette.cardStroke), lineWidth: 1)
        )
        .frame(width: 9, height: 9).accessibilityLabel(
            RecipeText.dotAccessibilityLabel(index: state.dotColourIndex)
        ).accessibilityAddTraits(.isImage)
    }
    @ViewBuilder private var actions: some View {
        if state.canMakeMain { Button(RecipeText.makeMain) { onAction(.makeMain(state.id)) } }
        Button(RecipeText.moveUp) { onAction(.moveUp(state.id)) }.disabled(!state.canMoveUp)
        Button(RecipeText.moveDown) { onAction(.moveDown(state.id)) }.disabled(!state.canMoveDown)
        Divider()
        Button(RecipeText.remove, role: .destructive) { onAction(.remove(state.id)) }
    }
    private func faceName(_ name: String, size: CGFloat, own: Bool) -> some View {
        let font: Font
        if own {
            do { font = Font(try renderer.font(for: .init(face: state.face, pointSize: size)).ctFont) } catch {
                fontFailures.record(error, face: state.id); font = .system(size: size)
            }
        } else {
            font = .system(size: size)
        }
        return Text(name).font(font).lineLimit(1).truncationMode(.tail).help(name)
    }
    private var adjustments: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(RecipeText.size) {
                HStack(spacing: 4) {
                    TextField(RecipeText.size, value: $draftSize, format: .number).frame(width: 52)
                        .id(sizeFieldIdentity).focused($sizeFocused).onSubmit { commitSize() }
                        .onChange(of: sizeFocused) { _, focused in if !focused { commitSize() } }
                        .accessibilityLabel(RecipeText.sizeAccessibilityLabel(family: state.face.family))
                    Text(RecipeText.percent)
                    Stepper(
                        RecipeText.size,
                        value: Binding(get: { state.sizePercent }, set: { onAction(.setSizePercent(state.id, $0)) }),
                        in: 10...1000, step: 5
                    )
                    .labelsHidden().accessibilityLabel(RecipeText.sizeAccessibilityLabel(family: state.face.family))
                }.help(RecipeText.sizeHelp)
            }
            LabeledContent(RecipeText.weight) {
                Picker(
                    RecipeText.weight,
                    selection: Binding(get: { state.weight }, set: { onAction(.setWeight(state.id, $0)) })
                ) {
                    ForEach(Array(RecipeText.weightMenuItems(selected: state.weight).enumerated()), id: \.offset) {
                        _, item in
                        Text(item.1).tag(item.0)
                    }
                }.pickerStyle(.menu).labelsHidden().help(RecipeText.weightHelp)
                    .accessibilityLabel(RecipeText.weightAccessibilityLabel(family: state.face.family))
            }
        }
    }
    private func commitSize() {
        let value = min(1000, max(10, draftSize))
        draftSize = value; onAction(.setSizePercent(state.id, value))
        // Recreate only the editor so an invalid numeric draft returns to the committed value.
        sizeFieldIdentity += 1
    }
}

@MainActor private final class RecipeLabelFontFailures {
    private var reported: Set<FaceKey> = []
    func record(_ error: any Error, face: FaceKey) {
        guard reported.insert(face).inserted else { return }
        NSLog("Recipe label font unavailable at %@: %@", face.description, String(describing: error))
    }
}
