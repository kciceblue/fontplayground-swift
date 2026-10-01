import Testing

@testable import FPAppUI

extension BuildFlowIntegration {
    @MainActor struct BackgroundAttentionTests {
        @Test("UI-M8: background build bounces the Dock once") func uiM8BackgroundBuildBouncesTheDock() async throws {
            for active in [false, true] {
                let r = try BuildTestRig(); defer { r.cleanup() }; r.system.isAppActive = active
                try await r.install()
                #expect(r.system.attentionCalls == (active ? 0 : 1))
                #expect(r.system.badges == (active ? [] : ["1"]))
                #expect(r.system.startedActivities.count == 1)
                #expect(r.system.endedActivities == r.system.startedActivities.map(\.0))
                r.model.appDidBecomeActive(); #expect(r.system.badges.last! == nil)
            }
            let r = try BuildTestRig(); defer { r.cleanup() }; r.system.isAppActive = false
            await r.startInstall(); r.engine.endWithoutResult(); await r.failed()
            #expect(r.system.attentionCalls == 1 && r.system.badges == ["1"])
            #expect(r.system.endedActivities == r.system.startedActivities.map(\.0))
            await r.startInstall(); await r.build.cancelAndWait()
            #expect(r.system.endedActivities == r.system.startedActivities.map(\.0))
            #expect(r.system.attentionCalls == 1)
        }
    }

}
