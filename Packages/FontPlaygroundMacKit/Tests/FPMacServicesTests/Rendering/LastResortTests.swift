import CoreText
import Foundation
import Testing

@testable import FPMacServices

struct LastResortTests {
    @Test func lastResortIsFoundByURLWithNameFallback() {
        let font = CTFontCreateWithFontDescriptor(LastResort.shared.descriptor, 20, nil)
        #expect(CTFontCopyPostScriptName(font) as String == "LastResort")
        #expect(
            (CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)?.path == "/System/Library/Fonts/LastResort.otf")
        let fallback = LastResort.make(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let fallbackFont = CTFontCreateWithFontDescriptor(fallback.descriptor, 20, nil)
        #expect(CTFontCopyPostScriptName(fallbackFont) as String == "LastResort")
    }
}
