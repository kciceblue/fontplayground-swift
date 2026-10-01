import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct NoticeTests {
    @Test func noticesReplaceByKindAndHaveExactTexts() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services)
        #expect(
            ShellText.unavailableOne(name: "A Regular")
                == "“A Regular” is no longer available. It stays in your font, marked as missing, until you replace or remove it."
        )
        #expect(
            ShellText.unavailableMany(count: 2, names: ShellText.quoted(["A Regular", "B Bold"]))
                == "2 fonts are no longer available: “A Regular”, “B Bold”. They stay in your font, marked as missing, until you replace or remove them."
        )
        #expect(
            ShellText.damaged(name: "last-damaged.fontrecipe")
                == "Your last recipe couldn't be read, so Font Playground started with an empty one. The file was kept as “last-damaged.fontrecipe”."
        )
        #expect(
            ShellText.engineUnavailable(reason: "missing")
                == "Font Playground can't start its font engine, so it can't list or build fonts: missing")
        #expect(
            ShellText.badFolders(paths: "“D:/Fonts”")
                == "Some saved font folders were ignored because they aren't valid on this Mac: “D:/Fonts”.")
        #expect(
            ShellText.fileDropped
                == "To use a font file, add the folder it's in with File › Add Font Folder…, or install it with Font Book."
        )
        #expect(
            ShellText.imported == "Imported your last recipe and settings from the earlier version of Font Playground.")
        #expect(
            ShellText.importFailed == "Font Playground found settings from an earlier version but couldn't read them.")
        #expect(ShellText.autosaveFailed(reason: "full") == "Font Playground couldn't save your recipe: full")
        #expect(ShellText.suggestion(missing: "A", replacement: "B") == "A isn't on this Mac. Use B instead?")
        m.postNotice(.init(kind: .engineUnavailable, text: "old"));
        let replacement = AppNotice(kind: .engineUnavailable, text: "new", revealURL: rig.temp.url);
        m.postNotice(replacement)
        #expect(m.notices == [replacement]); m.revealNotice(replacement);
        #expect(rig.system.revealed == [[rig.temp.url]])
        m.dismissNotice(replacement.id); #expect(m.notices.isEmpty)
    }
}
