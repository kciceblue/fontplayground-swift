import SwiftUI

public struct AppCommands: Commands {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }
    public static var menuOrder: [MenuCommand] { MenuCommand.allCases }
    public var body: some Commands {
        CommandGroup(replacing: .appInfo) { items(.appInfo) }
        CommandGroup(replacing: .newItem) { items(.newItem) }
        CommandGroup(before: .saveItem) { items(.beforeSaveItem) }
        CommandGroup(after: .pasteboard) { items(.afterPasteboard) }
        CommandGroup(before: .toolbar) {
            items(.beforeToolbar); Menu(ShellText.sampleText) { items(.sampleSubmenu) }
        }
        SidebarCommands()
        CommandMenu(ShellText.fontMenu) {
            command(.chooseMainFont)
            Menu(ShellText.addFontFor) { items(.addFontForSubmenu) }.disabled(!model.commandState.canAddFontFor)
            Divider()
            command(.advanced)
        }
        CommandGroup(replacing: .help) { items(.help) }
    }
    @ViewBuilder private func items(_ placement: MenuPlacement) -> some View {
        ForEach(Self.menuOrder.filter { $0.placement == placement }, id: \.self) { item in
            if item == .addFontForAnyLanguage { Divider() }
            command(item)
        }
    }
    @ViewBuilder private func command(_ item: MenuCommand) -> some View {
        if item == .colourByFont {
            Toggle(ShellText.colourByFont, isOn: $model.colourByFont)
        } else {
            Button(model.commandState.title(item)) { perform(item) }.keyboardShortcut(item.shortcut).disabled(
                !model.commandState.isEnabled(item))
        }
    }
    private func perform(_ item: MenuCommand) {
        switch item {
        case .about: model.showAbout()
        case .donate: model.openDonation()
        case .startOver: model.startOver()
        case .addFontFolder: model.addFontFolder()
        case .rescanFonts: model.rescanFonts()
        case .saveCopy: model.build.saveCopy()
        case .install: model.build.install()
        case .showInFinder: model.build.showInFinder()
        case .openInFontBook: model.build.openInFontBook()
        case .uninstall: model.build.uninstall()
        case .findFont: model.findFont()
        case .colourByFont: model.colourByFont.toggle()
        case .bigger: model.zoomPreviewIn()
        case .smaller: model.zoomPreviewOut()
        case .actualSize: model.resetPreviewZoom()
        case .sample(let id): model.applySample(id: id)
        case .sidebar: break  // SidebarCommands uses the native responder chain.
        case .chooseMainFont: model.openPicker(PickRequest(languageID: "latin", replaceKey: model.recipe.main?.key))
        case .addFontFor(let id): model.openPicker(PickRequest(languageID: id))
        case .addFontForAnyLanguage: model.openPicker(PickRequest(languageID: "any"))
        case .advanced: model.toggleAdvanced()
        case .help: model.openHelp()
        }
    }
}
