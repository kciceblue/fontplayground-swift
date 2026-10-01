import Foundation
import Testing

@testable import FPMacServices

struct PlatformFontPreferencesTests {
    @Test(
        "CATALOG-11: Chinese default is PingFang",
        .enabled(if: ProcessInfo.processInfo.environment["FP_APPLE_FONTS"] == "1"))
    func catalog11ChineseDefaultIsPingFang() async {
        let names = await PlatformFontPreferences.lookUp(probes: ["chinese_s": "你", "japanese": "こ", "latin": "a"])
        #expect(names["chinese_s"] == "PingFangSC-Regular")
        #expect(names["japanese"]?.hasPrefix("HiraginoSans") == true)
        #expect(names["latin"] == nil && names.values.allSatisfy { !$0.hasPrefix(".") })
    }
}
