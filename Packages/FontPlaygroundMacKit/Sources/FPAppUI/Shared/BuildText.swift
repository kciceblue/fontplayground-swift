import Foundation

public enum BuildText {
    public static let nameAccessibilityLabel = String(
        localized: "Font name", bundle: .module, comment: "build.name.accessibility")
    public static let styleAccessibilityLabel = String(
        localized: "Style name", bundle: .module, comment: "build.style.accessibility")
    public static let progressAccessibilityLabel = String(
        localized: "Building your font", bundle: .module, comment: "build.progress.accessibility")
    public static func progressAccessibilityValue(_ progress: Double) -> String {
        let percent = String(Int((min(1, max(0, progress)) * 100).rounded()))
        return String(localized: "\(percent) percent", bundle: .module, comment: "build.progress.value")
    }

    public static let starting = String(localized: "Starting…", bundle: .module, comment: "build.starting")
    public static let validate = String(localized: "Checking your fonts…", bundle: .module, comment: "build.validate")
    public static let plan = String(
        localized: "Deciding which font supplies each character…", bundle: .module, comment: "build.plan")
    public static let prepareAny = String(
        localized: "Preparing the fonts…", bundle: .module, comment: "build.prepareAny")
    public static let merge = String(localized: "Combining the fonts…", bundle: .module, comment: "build.merge")
    public static let finish = String(localized: "Finishing the font…", bundle: .module, comment: "build.finish")
    public static let verify = String(localized: "Checking the result…", bundle: .module, comment: "build.verify")
    public static let done = String(localized: "Done.", bundle: .module, comment: "build.done")
    public static let stopping = String(localized: "Stopping…", bundle: .module, comment: "build.stopping")
    public static let installingStatus = String(
        localized: "Installing your font…", bundle: .module, comment: "build.installingStatus")
    public static let savingStatus = String(
        localized: "Saving your font…", bundle: .module, comment: "build.savingStatus")
    public static let engineMissing = String(
        localized: "Font Playground can't find its font engine. Reinstall the app.", bundle: .module,
        comment: "build.engineMissing")
    public static let installedDetail = String(
        localized: "Choose it in any app's font list — apps that were already open may need to be reopened.",
        bundle: .module, comment: "build.installedDetail")
    public static let cancelled = String(localized: "Cancelled.", bundle: .module, comment: "build.cancelled")
    public static let idle = String(
        localized: "Installs in your Fonts folder — only for you, no password needed.", bundle: .module,
        comment: "build.idle")
    public static let install = String(localized: "Install", bundle: .module, comment: "build.install")
    public static let installing = String(localized: "Installing…", bundle: .module, comment: "build.installing")
    public static let saving = String(localized: "Saving…", bundle: .module, comment: "build.saving")
    public static let building = String(localized: "Building…", bundle: .module, comment: "build.building")
    public static let update = String(localized: "Update Installed Font", bundle: .module, comment: "build.update")
    public static let installed = String(localized: "Installed", bundle: .module, comment: "build.installed")
    public static let saveCopy = String(localized: "Save a Copy…", bundle: .module, comment: "build.saveCopy")
    public static let cancel = String(localized: "Cancel", bundle: .module, comment: "build.cancel")
    public static let showInFinder = String(localized: "Show in Finder", bundle: .module, comment: "build.showInFinder")
    public static let openInFontBook = String(
        localized: "Open in Font Book", bundle: .module, comment: "build.openInFontBook")
    public static let uninstall = String(localized: "Uninstall", bundle: .module, comment: "build.uninstall")
    public static let details = String(localized: "Details", bundle: .module, comment: "build.details")
    public static let name = String(localized: "Name", bundle: .module, comment: "build.name")
    public static let style = String(localized: "Style", bundle: .module, comment: "build.style")
    public static let namePlaceholder = String(
        localized: "Name your font", bundle: .module, comment: "build.namePlaceholder")
    public static let stylePlaceholder = String(
        localized: "Regular", bundle: .module, comment: "build.stylePlaceholder")
    public static let styleLeadingDot = String(
        localized: "A style name can't start with a dot.", bundle: .module, comment: "build.styleLeadingDot")
    public static let nameTooLong = String(
        localized: "Use a font name of at most 63 characters.", bundle: .module, comment: "build.nameTooLong")
    public static let styleTooLong = String(
        localized: "Use a style name of at most 63 characters.", bundle: .module, comment: "build.styleTooLong")
    public static let changeName = String(localized: "Change Name", bundle: .module, comment: "build.changeName")
    public static let installAnyway = String(
        localized: "Install Anyway", bundle: .module, comment: "build.installAnyway")
    public static let replace = String(localized: "Replace", bundle: .module, comment: "build.replace")
    public static let replaceInfo = String(
        localized: "The new font takes its place.", bundle: .module, comment: "build.replaceInfo")
    public static let downloadableInfo = String(
        localized: "If that font is downloaded later, apps may confuse it with yours.", bundle: .module,
        comment: "build.downloadableInfo")
    public static let hiddenName = String(
        localized: "Names that start with “.” are hidden by macOS — choose another name.", bundle: .module,
        comment: "build.hiddenName")
    public static let engineStopped = String(
        localized: "the font engine stopped unexpectedly.", bundle: .module, comment: "build.engineStopped")
    public static let timedOut = String(
        localized: "the font engine took too long.", bundle: .module, comment: "build.timedOut")
    public static let staleUnknown = String(
        localized: "A font changed since Font Playground last read it. Choose File › Rescan Fonts, then try again.",
        bundle: .module, comment: "build.staleUnknown")
    public static let removed = String(
        localized: "Removed from your fonts — it's in the Trash.", bundle: .module, comment: "build.removed")
    public static let notInstalled = String(
        localized: "That font was no longer installed.", bundle: .module, comment: "build.notInstalled")
    public static let fileGone = String(
        localized: "That file is no longer there.", bundle: .module, comment: "build.fileGone")
    public static let activity = String(localized: "Building a font", bundle: .module, comment: "build.activity")
    public static let appleSLA = String(
        localized: "Bundled with macOS: licensed for use on this Mac only; do not distribute the forged font.",
        bundle: .module, comment: "build.appleSLA")
    public static let microsoft = String(
        localized:
            "Supplied with a Microsoft product: licensed for use with that product only; do not distribute the forged font.",
        bundle: .module, comment: "build.microsoft")
    public static let unknownLicence = String(
        localized: "Licence unknown: check the source font's licence before you share the forged font.",
        bundle: .module, comment: "build.unknownLicence")
    public static func prepare(_ name: String) -> String {
        String(localized: "Preparing \(name)…", bundle: .module, comment: "build.prepare")
    }
    public static func buildingStatus(_ stage: String) -> String {
        String(localized: "Building your font — \(stage)", bundle: .module, comment: "build.buildingStatus")
    }
    public static func installedStatus(_ name: String) -> String {
        String(localized: "Installed as “\(name)”.", bundle: .module, comment: "build.installedStatus")
    }
    public static func savedStatus(_ path: String) -> String {
        String(localized: "Saved to \(path)", bundle: .module, comment: "build.savedStatus")
    }
    public static func buildError(_ reason: String) -> String {
        String(localized: "Couldn't build the font: \(reason)", bundle: .module, comment: "build.buildError")
    }
    public static func installError(_ reason: String) -> String {
        String(localized: "Couldn't install the font: \(reason)", bundle: .module, comment: "build.installError")
    }
    public static func saveError(_ reason: String) -> String {
        String(localized: "Couldn't save the font: \(reason)", bundle: .module, comment: "build.saveError")
    }
    public static func removeError(_ reason: String) -> String {
        String(localized: "Couldn't remove the font: \(reason)", bundle: .module, comment: "build.removeError")
    }
    public static func staleMaterial(_ name: String) -> String {
        String(
            localized:
                "“\(name)” changed since Font Playground last read it. Choose File › Rescan Fonts, then try again.",
            bundle: .module, comment: "build.staleMaterial")
    }
    public static func systemConflict(_ name: String) -> String {
        String(
            localized: "macOS already has a font called “\(name)” — choose another name.", bundle: .module,
            comment: "build.systemConflict")
    }
    public static func localConflict(_ name: String) -> String {
        String(
            localized: "A font called “\(name)” is already installed for everyone on this Mac — choose another name.",
            bundle: .module, comment: "build.localConflict")
    }
    public static func userConflict(_ name: String) -> String {
        String(
            localized: "You already have a font called “\(name)” installed — choose another name.", bundle: .module,
            comment: "build.userConflict")
    }
    public static func postscriptConflict(_ name: String) -> String {
        String(
            localized: "Another installed font already uses the internal name “\(name)” — choose another name.",
            bundle: .module, comment: "build.postscriptConflict")
    }
    public static func ownPostscriptConflict(_ name: String, _ postscript: String) -> String {
        String(
            localized: "Your font “\(name)” already uses the internal name “\(postscript)” — choose another name.",
            bundle: .module, comment: "build.ownPostscriptConflict")
    }
    public static func downloadableConflict(_ name: String) -> String {
        String(
            localized: "macOS can download a font called “\(name)”. Install yours under this name anyway?",
            bundle: .module, comment: "build.downloadableConflict")
    }
    public static func replaceConflict(_ name: String) -> String {
        String(
            localized: "Replace the “\(name)” you installed earlier?", bundle: .module, comment: "build.replaceConflict"
        )
    }
    public static func replaceError(_ new: String, _ old: String, _ reason: String) -> String {
        String(
            localized: "Installed “\(new)”, but couldn't remove “\(old)”: \(reason)", bundle: .module,
            comment: "build.replaceError")
    }
    public static func notes(_ number: String) -> String {
        String(localized: "Notes (\(number))", bundle: .module, comment: "build.notes")
    }
    public static func installedCatalogWarning(_ reason: String) -> String {
        String(
            localized: "The font is installed, but Font Playground couldn't refresh its font list: \(reason)",
            bundle: .module, comment: "build.installedCatalogWarning")
    }

}
