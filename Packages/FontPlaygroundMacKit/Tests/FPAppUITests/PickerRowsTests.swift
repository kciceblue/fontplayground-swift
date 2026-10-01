import FPCore
import Foundation
import Testing

@testable import FPAppUI

@MainActor struct PickerRowsTests {
    typealias F = PickerTestFaces
    @Test func languageFilterListsFamiliesThatDrawItWell() {
        let model = F.model("chinese_s")
        #expect(F.families(model) == ["Picker Simplified"])
        #expect(model.searchPlaceholder == "Search 1 font — English or native name")
        model.languageID = "any"
        #expect(F.families(model) == ["Picker Latin", "Picker Plain Han", "Picker Simplified", "Picker Zeta"])
        #expect(model.searchPlaceholder == "Search 4 fonts — English or native name")
        model.languageID = "latin"; #expect(F.families(model) == ["Picker Latin", "Picker Zeta"])
        model.languageID = "korean"; #expect(model.rows.isEmpty)
        #expect(model.statusText == "None of your fonts draw Korean well.")
    }
    @Test func searchMatchesEnglishAndNativeNames() {
        let model = F.model()
        for query in ["ZETA", "测试", "ＺＥＴＡ", "  zeta  "] {
            model.query = query; #expect(F.families(model) == ["Picker Zeta"])
        }
        #expect(model.currentRow?.nativeName == "测试黑体")
        model.query = "plain"; #expect(F.families(model) == ["Picker Plain Han"])
        model.query = "nothing like it"; #expect(model.rows.isEmpty && model.currentFace == nil && !model.isUseEnabled)
        #expect(model.statusText == "No fonts match “nothing like it”.")
        model.query = ""; #expect(F.families(model).count == 4 && model.statusText == "6 fonts")
    }
    @Test func sectionsAndCounts() {
        let model = F.model("chinese_s")
        #expect(F.rows(model) == ["All Chinese fonts · 1", "Picker Simplified"])
        model.languageID = "latin"; #expect(F.rows(model) == ["All Latin fonts · 2", "Picker Latin", "Picker Zeta"])
        #expect(!model.rows[0].isSelectable)
        model.languageID = "any"; #expect(F.rows(model).first == "All fonts · 4")
        model.query = "han"; #expect(F.rows(model) == ["All fonts · 1", "Picker Plain Han"])
    }
    @Test func suggestedSectionOnlyWithPassingSuggestions() {
        let model = F.model(context: F.context("latin", suggestions: [F.z]))
        #expect(
            F.rows(model) == [
                "Suggested for your text", "Picker Zeta", "All Latin fonts · 2", "Picker Latin", "Picker Zeta",
            ])
        #expect(model.currentRowID == model.rows[1].id)
        model.query = "latin"; #expect(F.rows(model) == ["All Latin fonts · 1", "Picker Latin"])
        model.open(F.context("latin", suggestions: [F.s]), catalog: F.catalog, status: .init())
        #expect(F.rows(model).first == "All Latin fonts · 2")
    }
    @Test func inYourFontTag() {
        let model = F.model(context: F.context("latin", keys: [F.lb.key]))
        #expect(model.rows[1].familyRow?.inRecipe == true)
        #expect(model.rows[2].familyRow?.inRecipe == false)
        #expect(PickerText.inYourFont == "in your font")
    }
    @Test("UI-1: hidden faces are never listed") func ui1HiddenFacesAreNeverListed() {
        let extra = [
            F.make(".Apple SD Gothic NeoI", points: F.han + F.latin, extra: ["hidden": true]),
            F.make("System Font", extra: ["postscript_name": ".SFNS-Regular"]),
            F.make(".LastResort", points: F.han + F.latin, extra: ["suspicious_coverage": true]),
        ]
        for language in Languages.all {
            let model = F.model(language.id.rawValue, catalog: F.catalog + extra)
            #expect(
                model.rows.compactMap(\.familyRow).allSatisfy {
                    !$0.family.hasPrefix(".") && $0.family != "System Font"
                })
            #expect(!model.useTitle.contains(".LastResort"))
            let baseline = F.model(language.id.rawValue)
            #expect(model.searchPlaceholder == baseline.searchPlaceholder)
        }
    }
    @Test("CATALOG-2: suspicious and hidden faces are never suggested")
    func catalog2SuspiciousAndHiddenFacesAreNeverSuggested() {
        let suspicious = F.make(".LastResort", points: F.han, extra: ["suspicious_coverage": true])
        let hidden = F.make(".Hiragino Sans GB Interface", points: F.han, extra: ["hidden": true])
        let model = F.model(context: F.context("chinese_s", suggestions: [suspicious, hidden]))
        #expect(!model.rows.contains { $0.id.section == .suggested })
        #expect(model.currentFace == F.s)
    }
    @Test("ADR-0008: unshapable fonts are hidden or greyed") func unshapableFontsHiddenOrGreyed() {
        let points = Array(UInt32(0x621)...0x64A) + F.latin
        let geeza = F.make("Geeza Pro", points: points, extra: ["shapes_groups": [], "aat": ["morx": true]])
        let noto = F.make("Noto Naskh Arabic", points: points, extra: ["shapes_groups": ["arabic"]])
        let model = F.model("arabic", catalog: [geeza, noto])
        #expect(F.families(model) == ["Noto Naskh Arabic"])
        #expect(model.unshapableCount == 1 && model.unshapableTitle == "Show fonts that can't shape Arabic (1)")
        model.showsUnshapable = true
        #expect(F.rows(model).suffix(2) == ["Can't shape Arabic · 1", "Geeza Pro"])
        #expect(model.rows.last?.familyRow?.unavailableReason == "Can't shape Arabic: its shaping is Apple-only")
        model.move(by: 1); #expect(model.currentFace == noto)
        model.languageID = "latin"; #expect(F.families(model) == ["Geeza Pro", "Noto Naskh Arabic"])
    }
}
