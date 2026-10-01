import Testing

@testable import FPMacServices

struct InstallFileNameTests {
    @Test func stemFollowsTheReference() {
        for (family, style, expected) in [
            ("Test Mix", "Regular", "Test Mix-Regular"), ("a/b:c", "B?", "a-b-c-B-"),
            ("  ", "", "Forged-Regular"), ("..Hidden", "Bold", "Hidden-Bold"),
            ("\u{3000}宋体\u{1C}", "Regular", "宋体-Regular"),
            ("A<>:\"/\\|?*B", "Regular", "A-B-Regular"),
            ("A\u{0}\u{1F}B", "Regular", "A-B-Regular"),
        ] { #expect(InstallFileName.stem(family: family, style: style) == expected) }
    }
}
