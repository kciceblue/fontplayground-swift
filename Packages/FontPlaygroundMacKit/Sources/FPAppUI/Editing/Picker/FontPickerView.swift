import FPCore
import SwiftUI

public struct FontPickerView: View {
    let model: AppModel
    @State private var cache: RowFontCache
    public init(model: AppModel) {
        self.model = model; _cache = State(initialValue: RowFontCache(renderer: model.renderer))
    }
    public var body: some View {
        @Bindable var picker = model.picker
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.cancelPicker()
            } label: {
                Label(PickerText.back, systemImage: "chevron.backward")
            }.buttonStyle(.link)
            Text(picker.title).accessibilityAddTraits(.isHeader).font(.title3.weight(.semibold))
            SearchFieldView(model: picker, visibleRows: { picker.visibleRowCount() }).frame(height: 24)
            // The note sits under the menu: side by side they left the sidebar's menu too narrow for its title.
            VStack(alignment: .leading, spacing: 4) {
                Picker(PickerText.languageLabel, selection: $picker.languageID) {
                    ForEach(Languages.all, id: \.id) { language in
                        Text(ModelText.languageLabel(language.id)).tag(language.id.rawValue)
                    }
                }.pickerStyle(.menu).fixedSize().accessibilityLabel(PickerText.languageLabel)
                if picker.language.id != .any {
                    Text(PickerText.filterNote).font(.caption).foregroundStyle(.secondary)
                }
            }
            if picker.unshapableCount > 0 {
                Toggle(picker.unshapableTitle, isOn: $picker.showsUnshapable).toggleStyle(.checkbox)
            }
            FontListView(model: picker, cache: cache).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(picker.statusText).font(.caption).foregroundStyle(.secondary).help(picker.statusHelp)
                if picker.status.isScanning {
                    ProgressView(value: Double(picker.status.done), total: Double(max(1, picker.status.total))).frame(
                        width: 120)
                }
            }
            if let row = picker.currentRow, row.styles.count > 1 {
                Picker(
                    PickerText.style,
                    selection: Binding<FaceKey?>(
                        get: { picker.currentFace?.key },
                        set: { key in
                            picker.chosenStyle = row.styles.first { $0.key == key }
                        })
                ) {
                    ForEach(row.styles, id: \.key) { face in Text(face.style).tag(Optional(face.key)) }
                }.pickerStyle(.menu).fixedSize()
            }
            HStack {
                Spacer()
                Button(PickerText.cancel) { model.cancelPicker() }.keyboardShortcut(.cancelAction)
                Button(picker.useTitle) { picker.choose() }.keyboardShortcut(.defaultAction).buttonStyle(
                    .borderedProminent
                ).disabled(!picker.isUseEnabled)
            }
        }.padding(12)
            .onChange(of: model.catalogFaces) { _, faces in picker.catalogChanged(faces, status: model.catalogStatus) }
            .onChange(of: model.catalogStatus) { _, status in picker.catalogChanged(model.catalogFaces, status: status)
            }
            .onDisappear { picker.cancel() }
    }
}
