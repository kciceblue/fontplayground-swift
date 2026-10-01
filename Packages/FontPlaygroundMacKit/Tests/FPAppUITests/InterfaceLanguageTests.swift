import AppKit
import Foundation
import Testing

@testable import FPAppUI

@MainActor struct InterfaceLanguageTests {
    @Test("CRIT-10: System resolves like the system (F5)") func resolvesLikeTheSystem() {
        let table: [([String], String)] = [
            (["zh-Hans-CN", "en"], "zh-Hans"), (["zh-CN"], "zh-Hans"), (["zh-SG"], "zh-Hans"),
            (["ja-JP", "zh-Hans"], "zh-Hans"), (["zh-Hant-TW", "zh-Hans-CN"], "zh-Hans"), (["zh-Hant-TW"], "en"),
            (["zh-HK"], "en"), (["ja-JP"], "en"), (["en-JP"], "en"), (["en-GB", "zh-Hans"], "en"),
        ]
        for (languages, expected) in table {
            #expect(InterfaceLanguage.system.resolved(systemLanguages: languages) == expected, "\(languages)")
            #expect(InterfaceLanguage.english.resolved(systemLanguages: languages) == "en")
            #expect(InterfaceLanguage.simplifiedChinese.resolved(systemLanguages: languages) == "zh-Hans")
        }
    }
    @Test func readsStoredOverrides() {
        let table: [([String]?, InterfaceLanguage)] = [
            (nil, .system), ([], .system), (["en"], .english), (["en-GB"], .english), (["zh-Hans"], .simplifiedChinese),
            (["zh-Hans-CN"], .simplifiedChinese), (["zh-CN"], .simplifiedChinese), (["zh-Hant-TW"], .system),
            (["ja"], .system),
        ]
        for (override, expected) in table { #expect(InterfaceLanguage(override: override) == expected) }
        for choice in InterfaceLanguage.allCases { #expect(InterfaceLanguage(override: choice.override) == choice) }
        #expect(InterfaceLanguage.system.override == nil && InterfaceLanguage.english.override == ["en"])
        #expect(InterfaceLanguage.simplifiedChinese.override == ["zh-Hans"])
    }
    @Test func titles() {
        #expect(InterfaceLanguage.allCases.map(\.title) == ["System", "English", "简体中文"])
    }
    @Test func choosingTheRunningLanguageDoesNotAsk() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services)
        m.setInterfaceLanguage(.english)
        #expect(rig.system.overrides == [["en"]] && m.interfaceLanguage == .english && m.languagePrompt == nil)
    }
    @Test func choosingAnotherLanguageAsksToReopen() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services)
        m.setInterfaceLanguage(.simplifiedChinese)
        #expect(rig.system.overrides == [["zh-Hans"]])
        // Settings presents the prompt; the main window's alert stays free (Codex review P2).
        #expect(m.alert == nil)
        let alert = try #require(m.languagePrompt)
        #expect(alert.title == ShellText.reopenTitle(language: "简体中文") && alert.message == ShellText.reopenMessage)
        #expect(alert.buttons.map(\.title) == [ShellText.quitAndReopen, ShellText.later])
        #expect(alert.buttons[0].isDefault && alert.buttons[1].role == .cancel)
        #expect(ShellText.reopenTitle(language: "简体中文") == "Reopen Font Playground in 简体中文?")
    }
    @Test func laterKeepsRunning() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services)
        m.setInterfaceLanguage(.simplifiedChinese); try #require(m.languagePrompt).buttons[1].action()
        #expect(rig.system.terminateCalls == 0 && m.interfaceLanguage == .simplifiedChinese && !m.relaunchRequested)
    }
    @Test func quitAndReopenRelaunchesOnce() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services)
        m.setInterfaceLanguage(.simplifiedChinese); try #require(m.languagePrompt).buttons[0].action()
        #expect(rig.system.terminateCalls == 1 && m.relaunchRequested)
        m.prepareForTermination(); #expect(rig.system.relaunchCalls == 1)
        m.prepareForTermination(); #expect(rig.system.relaunchCalls == 1)
    }
    @Test func systemChoiceFollowsTheSystem() throws {
        let rig = try ShellRig(); rig.system.systemLanguages = ["zh-Hans-CN"]; rig.system.languageOverride = ["en"]
        let m = AppModel(services: rig.services)
        #expect(m.interfaceLanguage == .english)
        m.setInterfaceLanguage(.system)
        #expect(rig.system.overrides == [nil] && rig.system.languageOverride == nil && m.languagePrompt != nil)
    }
    @Test func cancelledQuitForgetsTheRelaunch() async throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services)
        var alert: AlertContent?, replies: [Bool] = []
        let quit = QuitCoordinator(
            isBuilding: { true }, stopBuilding: {}, flush: {}, stopCatalog: {}, present: { alert = $0 },
            reply: { replies.append($0) }, closeWindow: {}, cancelled: { m.quitWasCancelled() })
        m.setInterfaceLanguage(.simplifiedChinese); try #require(m.languagePrompt).buttons[0].action()
        #expect(m.relaunchRequested && rig.system.terminateCalls == 1)
        #expect(quit.shouldTerminate() == .terminateLater)
        try #require(alert).buttons[1].action()
        #expect(replies == [false] && !m.relaunchRequested)
        m.prepareForTermination(); #expect(rig.system.relaunchCalls == 0)
    }
    @Test func liveOverrideUsesTheAppDomain() throws {
        let suite = "fp-test-language-" + UUID().uuidString, defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let live = LiveSystemActions(defaults: defaults, domain: suite)
        #expect(live.languageOverride == nil)
        live.setLanguageOverride(["zh-Hans"])
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["zh-Hans"])
        #expect(live.languageOverride == ["zh-Hans"])
        live.setLanguageOverride(nil)
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil && live.languageOverride == nil)
        #expect(
            LiveSystemActions.relaunchArguments(pid: 42, bundlePath: "/Applications/Font Playground.app") == [
                "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open \"$2\"",
                "fp-relaunch", "42", "/Applications/Font Playground.app",
            ])
    }
}
