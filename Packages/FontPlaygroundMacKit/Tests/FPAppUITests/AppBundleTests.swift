import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct AppBundleTests {
    @Test("UI-3: bundle metadata names the app and explains folder access") func ui3InfoPlistNamesTheApp() throws {
        var root = URL(fileURLWithPath: #filePath); for _ in 0..<5 { root.deleteLastPathComponent() }
        let plist = try #require(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: root.appending(path: "App/Info.plist")), format: nil) as? [String: Any])
        #expect(
            plist["CFBundleName"] as? String == "Font Playground"
                && plist["CFBundleDisplayName"] as? String == "Font Playground")
        #expect(
            plist["CFBundleIdentifier"] as? String == "$(PRODUCT_BUNDLE_IDENTIFIER)"
                && plist["CFBundleExecutable"] as? String == "$(EXECUTABLE_NAME)")
        #expect(plist["LSApplicationCategoryType"] as? String == "public.app-category.graphics-design")
        #expect(
            plist["CFBundleIconName"] as? String == "AppIcon"
                && plist["CFBundleAllowMixedLocalizations"] as? Bool == true)
        let fixed: [String: String] = [
            "CFBundleShortVersionString": "$(MARKETING_VERSION)",
            "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)", "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0", "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
            "CFBundleDevelopmentRegion": "en", "FPHelpURL": "",
            "FPDonateURL": "https://buymeacoffee.com/kciceblue",
        ]
        for (key, value) in fixed { #expect(plist[key] as? String == value) }
        #expect(plist["NSHighResolutionCapable"] as? Bool == true)
        let license = try String(contentsOf: root.appending(path: "LICENSE"), encoding: .utf8)
        #expect(
            plist["NSHumanReadableCopyright"] as? String
                == license.split(separator: "\n").first { $0.hasPrefix("Copyright") }.map(String.init))
        for key in ["NSRequiresAquaSystemAppearance", "UIDesignRequiresCompatibility", "LSUIElement"] {
            #expect(plist[key] == nil)
        }
        let usage = [
            "NSDocumentsFolderUsageDescription", "NSDesktopFolderUsageDescription", "NSDownloadsFolderUsageDescription",
            "NSRemovableVolumesUsageDescription", "NSNetworkVolumesUsageDescription",
        ]
        for key in usage {
            #expect(
                plist[key] as? String
                    == "Font Playground reads fonts in folders you add and saves fonts where you choose.")
        }
        let
            catalog = try #require(
                JSONSerialization.jsonObject(
                    with: Data(contentsOf: root.appending(path: "App/Resources/InfoPlist.xcstrings"))) as? [String: Any]
            ), strings = try #require(catalog["strings"] as? [String: [String: Any]])
        for key in usage + ["CFBundleName", "CFBundleDisplayName", "FPDonateURL"] {
            let languages = strings[key]?["localizations"] as? [String: [String: Any]],
                unit = languages?["en"]?["stringUnit"] as? [String: String]
            #expect(unit?["value"] == plist[key] as? String)
        }
        let yaml = try String(contentsOf: root.appending(path: "App/project.yml"), encoding: .utf8)
        for expected in [
            "PRODUCT_NAME: \"Font Playground\"", "PRODUCT_BUNDLE_IDENTIFIER: io.github.kciceblue.fontplayground",
            "MACOSX_DEPLOYMENT_TARGET: \"14.0\"", "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor", "- path: Resources", "product: FPAppUI",
        ] { #expect(yaml.contains(expected)) }
        #expect(!yaml.contains("CODE_SIGN_ENTITLEMENTS"))
        let app = try String(contentsOf: root.appending(path: "App/Sources/FontPlaygroundApp.swift"), encoding: .utf8)
        #expect(
            app.contains("NSApplicationDelegateAdaptor(FPAppDelegate.self)") && !app.contains("@main")
                && app.contains("Settings {") && !app.contains("WindowGroup"))
        let files = FileManager.default.enumerator(at: root.appending(path: "App"), includingPropertiesForKeys: nil)!
        #expect(!files.compactMap { $0 as? URL }.contains { $0.pathExtension == "entitlements" })
    }
}
extension AppBundleTests {
    @Test("CRIT-10: the app declares Simplified Chinese and its Chinese name") func crit10InfoPlistDeclaresChinese()
        throws
    {
        var root = URL(fileURLWithPath: #filePath); for _ in 0..<5 { root.deleteLastPathComponent() }
        let plist = try #require(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: root.appending(path: "App/Info.plist")), format: nil) as? [String: Any])
        #expect(plist["CFBundleLocalizations"] as? [String] == ["en", "zh-Hans"])
        #expect(plist["LSHasLocalizedDisplayName"] as? Bool == true)
        let catalog = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appending(path: "App/Resources/InfoPlist.xcstrings")))
                as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        func chinese(_ key: String) -> String? {
            ((strings[key]?["localizations"] as? [String: [String: Any]])?["zh-Hans"]?["stringUnit"]
                as? [String: String])?["value"]
        }
        #expect(chinese("CFBundleName") == "字体混搭" && chinese("CFBundleDisplayName") == "字体混搭")
        // D33: in Simplified Chinese, Donate… opens Afdian instead of Buy Me a Coffee.
        #expect(chinese("FPDonateURL") == "https://afdian.com/a/kciceblue")
        for key in [
            "NSDocumentsFolderUsageDescription", "NSDesktopFolderUsageDescription", "NSDownloadsFolderUsageDescription",
            "NSRemovableVolumesUsageDescription", "NSNetworkVolumesUsageDescription",
        ] {
            #expect(chinese(key) == "字体混搭会读取你添加的文件夹中的字体，并将字体存储到你选择的位置。")
        }
    }
}
