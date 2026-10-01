import FPCore
import SwiftUI

public struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selection: String?
    public init(model: AppModel) { self.model = model }
    public var body: some View {
        Form {
            Section {
                Picker(
                    ShellText.language,
                    selection: Binding(get: { model.interfaceLanguage }, set: model.setInterfaceLanguage)
                ) {
                    ForEach(InterfaceLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
                Picker(
                    ShellText.appearance,
                    selection: Binding(get: { model.settings.value.appearance }, set: model.setAppearance)
                ) {
                    Text(ShellText.system).tag(AppSettings.Appearance.system)
                    Text(ShellText.light).tag(AppSettings.Appearance.light)
                    Text(ShellText.dark).tag(AppSettings.Appearance.dark)
                }.pickerStyle(.segmented)
            } footer: {
                Text(ShellText.languageFooter)
            }
            Section {
                List(model.settings.value.extraFolders, id: \.self, selection: $selection) { folder in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(URL(fileURLWithPath: folder).lastPathComponent)
                        if let issue = model.folderIssues[folder] {
                            HStack {
                                DecorativeSymbol("exclamationmark.triangle"); Text(issue)
                            }.foregroundStyle(.red).font(.caption)
                        } else {
                            Text(ShellText.shortPath(folder)).foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }.frame(minHeight: 100, idealHeight: 140)
                HStack {
                    IconButton(symbol: "plus", label: ShellText.addFontFolderAccessibilityLabel) {
                        model.addFontFolder()
                    }
                    IconButton(symbol: "minus", label: ShellText.removeFolderAccessibilityLabel) {
                        if let folder = selection { model.removeFontFolder(folder); selection = nil }
                    }.disabled(selection == nil)
                }
            } header: {
                Text(ShellText.fontFolders).accessibilityAddTraits(.isHeader)
            } footer: {
                Text(ShellText.folderFooter)
            }
            Section {
                Button(ShellText.showSettingsFolder) { model.showSettingsFolderInFinder() }
                Button(ShellText.getMoreFonts) { model.getMoreFonts() }.disabled(
                    !model.services.system.isFontBookAvailable)
            } footer: {
                Text(ShellText.fontBookFooter)
            }
        }.formStyle(.grouped).frame(width: 480)
            // The language prompt belongs to Settings, where the choice was made, not to the main window.
            .contentAlert($model.languagePrompt)
    }
}
