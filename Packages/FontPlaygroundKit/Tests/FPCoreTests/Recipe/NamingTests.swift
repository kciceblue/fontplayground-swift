import FPCore
import Testing

struct NamingTests {
    @Test(arguments: [
        ("Microsoft YaHei", "YaHei"), ("MS Gothic", "Gothic"), ("Adobe Song Std", "Song Std"),
        ("Google Sans", "Sans"), ("microsoft ms Mincho", "Mincho"), ("Segoe UI", "Segoe UI"),
        ("Microsoft", "Microsoft"), ("  Noto  Sans  ", "Noto Sans"),
    ]) func stripVendor(input: String, expected: String) { #expect(Naming.stripVendor(input) == expected) }

    @Test func familyNamePairsMainAndSecond() {
        let segoe = fakeFace(cps("a"), family: "Segoe UI")
        let yahei = fakeFace(cps("a"), family: "Microsoft YaHei")
        #expect(Naming.defaultFamilyName([segoe, yahei]) == "Segoe UI YaHei")
        #expect(Naming.defaultFamilyName([yahei, segoe]) == "YaHei Segoe UI")
    }

    @Test func familyNameFallsBackToForged() {
        #expect(Naming.defaultFamilyName([]) == "Forged")
        #expect(Naming.defaultFamilyName([fakeFace(cps("a"), family: "Microsoft JhengHei")]) == "JhengHei Forged")
        let long = fakeFace(cps("a"), path: "a.ttf", family: "Source Han Sans HW SC")
        let other = fakeFace(cps("b"), path: "b.ttf", family: "Bahnschrift SemiCondensed")
        #expect(Naming.defaultFamilyName([long, other]) == "Source Han Sans HW SC Forged")
        let regular = fakeFace(cps("a"), path: "r.ttf", family: "Noto Sans")
        let bold = fakeFace(cps("a"), path: "b.ttf", family: "Noto Sans", style: "Bold")
        let third = fakeFace(cps("a"), path: "c.ttf", family: "Noto Serif")
        #expect(Naming.defaultFamilyName([regular, bold]) == "Noto Sans Forged")
        #expect(Naming.defaultFamilyName([regular, bold, third]) == "Noto Sans Noto Serif")
        let combining = fakeFace(cps("a"), family: String(repeating: "e\u{301}", count: 15))
        #expect(Naming.defaultFamilyName([combining, third]) == combining.family + " Forged")
    }

    @Test func defaultStyleFollowsMain() {
        #expect(Naming.defaultStyle(fakeFace(cps("a"), style: "Semibold Italic")) == "Semibold Italic")
        #expect(Naming.defaultStyle(fakeFace(cps("a"), style: "  ")) == "Regular")
        #expect(Naming.defaultStyle(nil) == "Regular")
        #expect(Naming.defaultStyle(fakeFace(cps("a"), style: " Bold ")) == " Bold ")
    }

    @Test func fileNameReplacesUnsafeRuns() {
        #expect(Naming.fileName(family: "Segoe UI YaHei", style: "Regular") == "Segoe UI YaHei-Regular.ttf")
        #expect(Naming.fileName(family: "A/B:C?", style: "Bold") == "A-B-C--Bold.ttf")
        #expect(Naming.fileName(family: "  ", style: "") == "Forged-Regular.ttf")
        #expect(Naming.fileName(family: "A<>:\"/\\|?*\u{0}\u{1F}B", style: "R") == "A-B-R.ttf")
    }

    @Test func cleanNameUsesThePythonWhitespaceSet() {
        #expect(Naming.cleanName("\u{1C}\u{85}A B\u{3000}") == "A B")
        #expect(Naming.cleanName("\u{200B}A") == "\u{200B}A")
        #expect(Naming.stripVendor("Microsoft\u{3000}YaHei") == "YaHei")
        let values: [UInt32] =
            Array(9...13) + Array(28...32) + [0x85, 0xA0, 0x1680]
            + Array(0x2000...0x200A) + [0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
        for value in values {
            let space = String(Unicode.Scalar(value)!)
            #expect(Naming.cleanName(space + "A B" + space) == "A B")
        }
    }
}
