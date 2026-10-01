import FPMacServices

public enum ConflictText {
    public static func title(for reason: ConflictReason) -> String {
        switch reason {
        case .systemHas(let name): BuildText.systemConflict(name)
        case .installedForEveryone(let name): BuildText.localConflict(name)
        case .youHave(let name): BuildText.userConflict(name)
        case .internalNameInUse(let name): BuildText.postscriptConflict(name)
        case .internalNameUsedByYourFont(let name, let fullName): BuildText.ownPostscriptConflict(fullName, name)
        case .hiddenName: BuildText.hiddenName
        case .appleOffersDownload(let name): BuildText.downloadableConflict(name)
        }
    }
    @MainActor public static func alert(
        for conflict: InstallConflict,
        onChangeName: @escaping @MainActor () -> Void, onConfirm: @escaping @MainActor () -> Void
    ) -> AlertContent? {
        switch conflict {
        case .noConflict: return nil
        case .block(let reason):
            return AlertContent(
                title: title(for: reason),
                buttons: [
                    .init(title: BuildText.changeName, isDefault: true, action: onChangeName)
                ])
        case .ask(let reason):
            return AlertContent(
                title: title(for: reason),
                message: { if case .appleOffersDownload = reason { BuildText.downloadableInfo } else { nil } }(),
                buttons: [
                    .init(title: BuildText.installAnyway, isDefault: true, action: onConfirm),
                    .init(title: BuildText.cancel, role: .cancel, action: {}),
                ])
        case .replaceOurs(let font):
            return AlertContent(
                title: BuildText.replaceConflict(font.fullName),
                message: BuildText.replaceInfo,
                buttons: [
                    .init(title: BuildText.replace, isDefault: true, action: onConfirm),
                    .init(title: BuildText.cancel, role: .cancel, action: {}),
                ])
        }
    }
}
