import Foundation
import Testing

@testable import FPMacServices

struct InstallTextTests {
    @Test func install2Install13EnglishTextMatchesSpec() {
        let font = InstalledFont(
            fileURL: URL(fileURLWithPath: "/temporary/F.ttf"), family: "F", style: "Regular",
            fullName: "F Regular", postscriptName: "F-Regular", sha256: "hash", size: 10, installedAt: .distantPast)
        let reasons: [(ConflictReason, String)] = [
            (.systemHas(name: "F"), "macOS already has a font called “F” — choose another name."),
            (
                .installedForEveryone(name: "F"),
                "A font called “F” is already installed for everyone on this Mac — choose another name."
            ),
            (.youHave(name: "F"), "You already have a font called “F” installed — choose another name."),
            (
                .internalNameInUse(postscriptName: "P"),
                "Another installed font already uses the internal name “P” — choose another name."
            ),
            (
                .internalNameUsedByYourFont(postscriptName: "P", fullName: "F Regular"),
                "Your font “F Regular” already uses the internal name “P” — choose another name."
            ),
            (.hiddenName, "Names that start with “.” are hidden by macOS — choose another name."),
            (
                .appleOffersDownload(name: "F"),
                "macOS can download a font called “F”. Install yours under this name anyway?"
            ),
        ]
        for (reason, expected) in reasons {
            #expect(reason.englishText == expected)
            #expect(InstallConflict.block(reason).englishText == expected)
            #expect(InstallConflict.ask(reason).englishText == expected)
        }
        let conflicts: [(InstallConflict, String)] = [
            (.replaceOurs(font), "Replace the “F Regular” you installed earlier?"),
            (.noConflict, "nothing is in the way"),
        ]
        for (conflict, expected) in conflicts { #expect(conflict.englishText == expected) }
        var errors: [(InstallError, String)] = [
            (.invalidQuery, "the font needs a name"), (.sourceMissing, "the built font file is missing"),
            (.unreadable, "macOS can't read this font file"),
            (.unexpectedName(expected: "A", found: "B"), "its internal name is “B”, not “A”"),
            (.notForged, "it wasn't made by Font Playground"),
            (.noFreeFileName(stem: "F-Regular"), "there's no free file name for “F-Regular” in your Fonts folder"),
            (.notOurs(name: "F"), "Font Playground didn't install “F”, so it won't remove it"),
            (
                .previousCopyNotRemoved(installed: font, previous: font, message: "Denied"),
                "Installed “F Regular”, but couldn't remove “F Regular”: Denied"
            ),
            (.manifestUnsupported, "the list of fonts Font Playground installed was written by a newer version"),
            (.fileSystem(operation: "stage", message: "Permission denied"), "Permission denied"),
        ]
        errors += conflicts.map { (.conflict($0.0), $0.1) }
        errors += reasons.flatMap { [(.conflict(.block($0.0)), $0.1), (.conflict(.ask($0.0)), $0.1)] }
        for (error, expected) in errors {
            #expect(error.englishText == expected)
            #expect((error as Error).localizedDescription == expected)
            #expect(!error.englishText.contains("Windows"))
        }
        #expect(UninstallOutcome.movedToTrash(nil).englishText == "Removed from your fonts — it's in the Trash.")
        #expect(UninstallOutcome.notInstalled.englishText == "That font was no longer installed.")
    }
}
