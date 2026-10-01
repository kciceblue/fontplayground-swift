import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct AboutCreditsTests {
    @Test func creditsCarryTheLicenceNoteAndAcknowledgements() {
        let hello = EngineHello(
            fpengineVersion: "1", python: "3.12", fonttools: "4.60", platform: "darwin", capabilities: [])
        let text = AboutCredits.make(hello: hello, acknowledgements: "MIT text")
        #expect(
            text
                == "Font Playground doesn't include or sell any fonts. Fonts you forge keep their sources' licences; Font Playground tells you what it knows about them, but it is up to you to respect them.\n\nFont engine: fpengine 1, fontTools 4.60, Python 3.12\n\nAcknowledgements\nMIT text"
        )
        #expect(AboutCredits.make(hello: nil, acknowledgements: nil) == ShellText.licenceNote)
    }
}
