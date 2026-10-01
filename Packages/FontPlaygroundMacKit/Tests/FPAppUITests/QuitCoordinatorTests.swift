import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct QuitCoordinatorTests {
    @Test("UI-10: quitting during a build uses verb buttons") func ui10QuitWhileBuildingAsksWithVerbButtons()
        async throws
    {
        var building = true, events: [String] = [], alert: AlertContent?
        let q = QuitCoordinator(
            isBuilding: { building },
            stopBuilding: {
                events.append("stop"); building = false
            }, flush: { events.append("flush") }, stopCatalog: { events.append("stopCatalog") },
            present: { alert = $0 }, reply: { events.append("reply:\($0)") }, closeWindow: { events.append("close") })
        #expect(q.shouldTerminate() == .terminateLater)
        let shown = try #require(alert)
        #expect(
            shown.title == "Your font is still being built. Quit anyway?"
                && shown.buttons.map(\.title) == ["Quit", "Keep Building"])
        #expect(shown.buttons[0].isDefault && shown.buttons[1].role == .cancel)
        #expect(q.shouldTerminate() == .terminateCancel && alert?.id == shown.id)
        shown.buttons[1].action(); #expect(events == ["reply:false"])
        #expect(q.shouldTerminate() == .terminateLater); events = []; alert?.buttons[0].action();
        await shellEventually { events.count == 4 }
        #expect(events == ["stop", "flush", "stopCatalog", "reply:true"])
        // Not building: AppKit's reply still waits until the catalog scan (and its helper) has stopped.
        events = []; #expect(q.shouldTerminate() == .terminateLater)
        await shellEventually { events.count == 3 }
        #expect(events == ["flush", "stopCatalog", "reply:true"])
    }
    @Test("UI-15: closing asks while building and then quits") func ui15ClosingTheWindowQuitsAndAsksWhileBuilding()
        async throws
    {
        let rig = try ShellRig(), delegate = FPAppDelegate(services: rig.services)
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        var alert: AlertContent?, events: [String] = []
        let q = QuitCoordinator(
            isBuilding: { true }, stopBuilding: { events.append("stop") }, flush: { events.append("flush") },
            stopCatalog: { events.append("stopCatalog") }, present: { alert = $0 },
            reply: { events.append("reply:\($0)") }, closeWindow: { events.append("close") })
        #expect(!q.windowShouldClose()); let first = try #require(alert);
        #expect(!q.windowShouldClose() && alert?.id == first.id)
        first.buttons[1].action(); #expect(events.isEmpty)
        #expect(!q.windowShouldClose()); alert?.buttons[0].action(); await shellEventually { events.count == 2 }
        #expect(events == ["stop", "close"] && q.windowShouldClose())
    }
}
