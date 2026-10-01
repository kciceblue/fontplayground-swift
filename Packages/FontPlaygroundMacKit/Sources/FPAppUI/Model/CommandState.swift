import FPCore

public struct CommandState: Equatable {
    public let canStartOver, canRescan, canFindFont, canChooseMainFont, canAddFontFor, canZoomIn, canZoomOut,
        canResetZoom, canOpenHelp, canDonate: Bool
    public let isColourByFontOn: Bool
    private let hasMain: Bool
    private let inspectorPresented: Bool
    private let build: BuildCommands
    public init(
        recipe: Recipe, isBuilding: Bool, catalogIsEmpty: Bool, isScanning: Bool, engineStatus: EngineStatus,
        previewPointSize: Int, colourByFont: Bool, inspectorPresented: Bool, helpAvailable: Bool,
        donateAvailable: Bool, build: BuildCommands
    ) {
        hasMain = recipe.main != nil; self.inspectorPresented = inspectorPresented; self.build = build
        canStartOver = !recipe.materials.isEmpty || isBuilding
        if case .unavailable = engineStatus { canRescan = false } else { canRescan = !isScanning }
        canFindFont = !isBuilding && !catalogIsEmpty; canChooseMainFont = canFindFont
        canAddFontFor = !isBuilding && hasMain
        canZoomIn = previewPointSize < 96; canZoomOut = previewPointSize > 10; canResetZoom = previewPointSize != 30
        canOpenHelp = helpAvailable; canDonate = donateAvailable; isColourByFontOn = colourByFont
    }
    public func isEnabled(_ command: MenuCommand) -> Bool {
        switch command {
        case .startOver: canStartOver
        case .rescanFonts: canRescan
        case .saveCopy: build.canSaveCopy
        case .install: build.canInstall
        case .showInFinder: build.canShowInFinder
        case .openInFontBook: build.canOpenInFontBook
        case .uninstall: build.canUninstall
        case .findFont: canFindFont
        case .bigger: canZoomIn
        case .smaller: canZoomOut
        case .actualSize: canResetZoom
        case .chooseMainFont: canChooseMainFont
        case .addFontFor, .addFontForAnyLanguage: canAddFontFor
        case .help: canOpenHelp
        case .donate: canDonate
        default: true
        }
    }
    public func title(_ command: MenuCommand) -> String {
        switch command {
        case .chooseMainFont: hasMain ? ShellText.changeMain : ShellText.chooseMain
        case .advanced: inspectorPresented ? ShellText.hideAdvanced : ShellText.showAdvanced
        case .install: build.installTitle
        default: command.defaultTitle
        }
    }
}
