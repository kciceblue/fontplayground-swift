import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct DonationTests {
    static let url = URL(string: "https://buymeacoffee.com/kciceblue")!
    /// A rig whose services carry the donation page; `defaults` lets a second launch share the first one's settings.
    static func services(_ rig: ShellRig, defaults: UserDefaults? = nil) -> AppServices {
        var services = rig.services; services.donateURL = url
        if let defaults { services.defaults = defaults }
        return services
    }
    @Test func theFirstReadyLaunchOffersTheDonationPageOnce() async throws {
        let rig = try ShellRig(), m = AppModel(services: Self.services(rig))
        await rig.ready(m)
        let offer = try #require(m.alert)
        #expect(offer.title == "Support Font Playground")
        #expect(
            offer.message
                == "Font Playground is free. If you find it useful, you can buy me a coffee to support its development. You won't see this message again, but Font Playground › Donate… is always there."
        )
        #expect(offer.buttons.map(\.title) == ["Buy Me a Coffee", "No Thanks"])
        #expect(offer.buttons[0].isDefault && offer.buttons[1].role == .cancel)
        #expect(m.settings.donationOffered && rig.temp.defaults.bool(forKey: "donationOffered"))
        offer.buttons[0].action(); #expect(rig.system.openedURLs == [Self.url])
        let second = try ShellRig(), next = AppModel(services: Self.services(second, defaults: rig.temp.defaults))
        await second.ready(next)
        #expect(next.alert == nil && second.system.openedURLs.isEmpty)
    }
    @Test func noThanksOpensNothingAndStillCountsAsOffered() async throws {
        let rig = try ShellRig(), m = AppModel(services: Self.services(rig))
        await rig.ready(m)
        try #require(m.alert).buttons[1].action()
        #expect(rig.system.openedURLs.isEmpty)
        #expect(SettingsStore(defaults: rig.temp.defaults, probe: rig.probe).donationOffered)
    }
    @Test func anotherAlertDefersTheOfferToALaterLaunch() async throws {
        let rig = try ShellRig(), m = AppModel(services: Self.services(rig))
        await m.start(); await shellEventually { await rig.catalog.refreshModes.count == 1 }
        m.alert = AlertContent(title: "Start over?", buttons: [])
        await rig.catalog.finishRefresh(with: ShellSnapshot.make(faces: []))
        await shellEventually { m.launchPhase == .ready }
        #expect(m.alert?.title == "Start over?" && !m.settings.donationOffered)
        let second = try ShellRig(), next = AppModel(services: Self.services(second, defaults: rig.temp.defaults))
        await second.ready(next)
        #expect(next.alert?.title == "Support Font Playground" && next.settings.donationOffered)
    }
    @Test func withoutAPageThereIsNoOfferAndDonateIsDisabled() async throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services)
        await rig.ready(m)
        #expect(m.alert == nil && !m.settings.donationOffered && !m.commandState.isEnabled(.donate))
        m.openDonation(); #expect(rig.system.openedURLs.isEmpty)
        let linked = AppModel(services: Self.services(rig))
        #expect(linked.commandState.isEnabled(.donate))
        linked.openDonation(); #expect(rig.system.openedURLs == [Self.url])
    }
    @Test func theOfferedFlagReadsOnlyABool() throws {
        let rig = try ShellRig(), d = rig.temp.defaults
        #expect(!SettingsStore(defaults: d, probe: rig.probe).donationOffered)
        // UserDefaults skips a write whose value isEqual the stored one (1 == true), so clear the key each time.
        for (value, expected) in [("yes", false), (1, false), (true, true)] as [(Any, Bool)] {
            d.removeObject(forKey: "donationOffered"); d.set(value, forKey: "donationOffered")
            #expect(SettingsStore(defaults: d, probe: rig.probe).donationOffered == expected, "\(value)")
        }
    }
}
