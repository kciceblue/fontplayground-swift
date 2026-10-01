import FPCore
import SwiftUI

@MainActor public struct ActionBarView: View {
    let model: AppModel
    @FocusState private var nameFocused: Bool
    public static let primaryShortcut: KeyboardShortcut? = nil
    public static let cancelShortcut = KeyboardShortcut.cancelAction
    /// A saved path truncates in the middle (its tooltip has it all); other statuses wrap at half-screen width.
    public static func statusLineLimit(saved: Bool) -> Int { saved ? 1 : 3 }
    public init(model: AppModel) { self.model = model }
    public static func familyBinding(_ model: AppModel) -> Binding<String> {
        Binding(get: { model.recipe.names.family }, set: { text in model.edit { $0.setFamily(text, byUser: true) } })
    }
    public static func styleBinding(_ model: AppModel) -> Binding<String> {
        Binding(get: { model.recipe.names.style }, set: { text in model.edit { $0.setStyle(text, byUser: true) } })
    }
    public var body: some View {
        let state = model.build.actionBarState
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                fields(state)
                status(state).frame(minWidth: 120)
                buttons(state, compact: false)
            }
            VStack(alignment: .leading, spacing: 10) {
                fields(state)
                HStack(spacing: 14) {
                    status(state).frame(minWidth: 120)
                    buttons(state, compact: false)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                fields(state)
                HStack(spacing: 10) {
                    status(state)
                    buttons(state, compact: true)
                }
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
        .background(.bar).overlay(alignment: .top) { Divider() }
        .onChange(of: model.build.nameFocusRequest) { _, _ in nameFocused = true }
    }
    private func fields(_ state: ActionBarState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(BuildText.name).font(.caption).foregroundStyle(.secondary)
                TextField(BuildText.namePlaceholder, text: Self.familyBinding(model))
                    .accessibilityLabel(BuildText.nameAccessibilityLabel).focused($nameFocused)
            }.frame(minWidth: 200, idealWidth: 230, maxWidth: 260)
            VStack(alignment: .leading, spacing: 3) {
                Text(BuildText.style).font(.caption).foregroundStyle(.secondary)
                TextField(BuildText.stylePlaceholder, text: Self.styleBinding(model))
                    .accessibilityLabel(BuildText.styleAccessibilityLabel)
            }.frame(minWidth: 90, idealWidth: 100, maxWidth: 120)
        }.disabled(!state.namesEditable)
    }
    private func status(_ state: ActionBarState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                switch state.tone {
                case .ok: DecorativeSymbol("checkmark.circle.fill").foregroundStyle(.green)
                case .warn: DecorativeSymbol("exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .danger: DecorativeSymbol("xmark.octagon.fill").foregroundStyle(.red)
                default: EmptyView()
                }
                Text(state.status).lineLimit(Self.statusLineLimit(saved: model.build.state == .saved))
                    .truncationMode(model.build.state == .saved ? .middle : .tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(model.build.state == .saved ? (model.build.savedURL?.path ?? state.status) : state.status)
            }
            if let progress = state.progress {
                ProgressView(value: progress).accessibilityLabel(BuildText.progressAccessibilityLabel)
                    .accessibilityValue(BuildText.progressAccessibilityValue(progress))
            } else {
                ForEach(Array(state.detailLines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    ForEach(Array(state.links.enumerated()), id: \.offset) { _, link in
                        Button(linkTitle(link)) { follow(link) }.buttonStyle(.link).font(.caption)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func buttons(_ state: ActionBarState, compact: Bool) -> some View {
        HStack(spacing: 8) {
            if state.showsCancel {
                Button(BuildText.cancel) { model.build.cancel() }.disabled(!state.cancelEnabled)
                    .keyboardShortcut(Self.cancelShortcut)
            }
            if state.showsSaveCopy && !compact {
                Button(BuildText.saveCopy) { model.build.saveCopy() }.disabled(!state.saveCopyEnabled)
            }
            // Compact lets the button shrink to its title, leaving the wrapping status room for two lines.
            Button {
                model.build.install()
            } label: {
                HStack {
                    if state.primaryIsDone { DecorativeSymbol("checkmark") }
                    Text(state.primaryTitle)
                }.frame(minWidth: compact ? nil : 140)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!state.primaryEnabled)
        }.fixedSize()
    }
    private func linkTitle(_ link: ActionBarState.LinkKind) -> String {
        switch link {
        case .showInFinder: BuildText.showInFinder
        case .openInFontBook: BuildText.openInFontBook
        case .uninstall: BuildText.uninstall
        case .notes(let count): BuildText.notes(count.formatted(.number))
        case .details: BuildText.details
        }
    }
    private func follow(_ link: ActionBarState.LinkKind) {
        switch link {
        case .showInFinder: model.build.showInFinder()
        case .openInFontBook: model.build.openInFontBook()
        case .uninstall: model.build.uninstall()
        case .notes, .details: model.build.showReport()
        }
    }
}
