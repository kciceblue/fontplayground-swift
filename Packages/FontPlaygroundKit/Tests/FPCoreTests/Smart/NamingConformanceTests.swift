import FPCore
import Foundation
import Testing

struct NamingConformanceTests {
    private struct FamilyFixture: Decodable {
        struct FamilyCase: Decodable { var families: [String]; var expected: String }
        var stripVendor: [[String]]
        var defaultFamilyName: [FamilyCase]
        var defaultStyle: [[String?]]
        var fileStem: [[String]]
        enum CodingKeys: String, CodingKey {
            case stripVendor = "strip_vendor", defaultFamilyName = "default_family_name"
            case defaultStyle = "default_style", fileStem = "file_stem"
        }
    }
    private struct PSFixture: Decodable { var cases: [[String]] }

    @Test func fixtureCasesMatch() throws {
        let fixture = try Fixtures.load(FamilyFixture.self, "naming/family-names.json")
        var checked = 0, skipped = 0
        for row in fixture.stripVendor {
            if row[0].hasPrefix(".") { skipped += 1; continue }
            #expect(Naming.stripVendor(row[0]) == row[1]); checked += 1
        }
        for row in fixture.defaultFamilyName {
            if row.families.contains(where: { $0.hasPrefix(".") }) { skipped += 1; continue }
            #expect(Naming.defaultFamilyName(row.families.map { fakeFace(.empty, family: $0) }) == row.expected)
            checked += 1
        }
        for row in fixture.defaultStyle {
            let face = row[0].map { fakeFace(.empty, style: $0) }
            #expect(Naming.defaultStyle(face) == row[1]); checked += 1
        }
        for row in fixture.fileStem {
            if row[0].hasPrefix(".") { skipped += 1; continue }
            #expect(Naming.fileName(family: row[0], style: row[1]) == row[2] + ".ttf"); checked += 1
        }
        print("Naming fixture: \(checked) cases checked; \(skipped) leading-dot cases use the macOS refinement")
        #expect(checked >= 50)
    }

    @Test func defaultNamesNeverStartWithADot() {
        #expect(
            Naming.defaultFamilyName([fakeFace(.empty, family: ".SF Arabic"), fakeFace(.empty, family: "PingFang SC")])
                == "SF Arabic PingFang SC")
        #expect(
            Naming.defaultFamilyName([fakeFace(.empty, family: "..."), fakeFace(.empty, family: "MS .Hidden")])
                == "Hidden Forged")
        #expect(Naming.defaultFamilyName([fakeFace(.empty, family: "...")]) == "Forged")
        #expect(Naming.fileName(family: ".Hidden", style: "Regular") == "Hidden-Regular.ttf")
        #expect(Naming.fileName(family: ".\u{0301}Hidden", style: "Regular") == "\u{0301}Hidden-Regular.ttf")
        #expect(Naming.fileName(family: "...\u{001C}Hidden", style: "Regular") == "-Hidden-Regular.ttf")
        #expect(Naming.fileName(family: ".　Hidden", style: "Regular") == "Hidden-Regular.ttf")
    }

    @Test func postscriptNamesMatchFixture() throws {
        let fixture = try Fixtures.load(PSFixture.self, "naming/postscript_names.json")
        #expect(fixture.cases.count >= 12)
        for row in fixture.cases {
            let name = Naming.postscriptName(family: row[0], style: row[1])
            #expect(name == row[2])
            #expect(name.utf8.count <= 63)
            #expect(name.range(of: "^[A-Za-z0-9]+-[A-Za-z0-9]+$", options: .regularExpression) != nil)
        }
        print("PostScript fixture: \(fixture.cases.count) cases checked")
    }
}

struct PostScriptNameTests {
    @Test func workedExamplesMatchTheEngine() {
        let cases = [
            ("Avenir Next PingFang", "Regular", "AvenirNextPingFangFP61d27706-Regular"),
            ("Avenir Next", "Regular", "AvenirNextFP76fdbbf4-Regular"),
            ("我的字体", "Regular", "ForgedFP5ef09893-Regular"), ("你的字体", "Regular", "ForgedFP4f4f31c7-Regular"),
            ("Noto 我的", "Regular", "NotoFP193bc651-Regular"), ("Noto 你的", "Regular", "NotoFP39174c89-Regular"),
            ("甲字体", "粗体", "ForgedFP4baff28f-Regular"), ("甲字体", "细体", "ForgedFP865d96ec-Regular"),
            ("My Font", "Bold Italic", "MyFontFP072c765b-BoldItalic"),
            ("MyFont", "Bold Italic", "MyFontFP3601e1d1-BoldItalic"),
            ("  Forged Test ", " Regular ", "ForgedTestFP373d14cc-Regular"),
            (
                "A Very Long Family Name That Keeps Going And Going Forever", "Extra Condensed Semibold Italic",
                "AVeryLongFamilyNameThatKeepsGoinFP4bedb3c1-ExtraCondensedSemibo"
            ),
            ("", "Regular", "ForgedFP55a0a3da-Regular"),
        ]
        for (family, style, expected) in cases {
            #expect(Naming.postscriptName(family: family, style: style) == expected)
        }
        #expect(Naming.fnv1a64([]) == 0xcbf29ce484222325)
        #expect(Naming.fnv1a64(Array("a".utf8)) == 0xaf63dc4c8601ec8c)
        #expect(
            Naming.postscriptName(family: "Café", style: "Regular")
                != Naming.postscriptName(family: "Cafe\u{0301}", style: "Regular"))
    }
}
