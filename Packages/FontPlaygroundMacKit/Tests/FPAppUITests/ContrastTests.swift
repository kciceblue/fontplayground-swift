import AppKit
import Testing

@testable import FPAppUI

@MainActor struct ContrastTests {
    private func luminance(_ rgb: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let value = Double((rgb >> shift) & 255) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
    private func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let a = luminance(a), b = luminance(b)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    @Test("UI-M4: every palette variant meets WCAG contrast rules") func uiM4PaletteMeetsTheContrastRules() {
        #expect(abs(ratio(0x000000, 0xffffff) - 21) < 0.001)
        #expect(abs(ratio(0x777777, 0xffffff) - 4.48) < 0.01)
        for dark in [false, true] {
            for contrast in [false, true] {
                let background: UInt32 = dark ? 0x1e1e1e : 0xffffff
                for index in 0..<4 {
                    #expect(
                        ratio(MixPalette.hex(forMaterialAt: index, dark: dark, increasedContrast: contrast), background)
                            >= (contrast ? 7 : 4.5))
                }
                let missing = MixPalette.missingHex(dark: dark, increasedContrast: contrast)
                #expect(ratio(missing, dark ? 0xffffff : 0x000000) >= 7)
                #expect(ratio(missing, background) >= (contrast ? 2.2 : 1.6))
                #expect(
                    ratio(MixPalette.cardStrokeHex(dark: dark, increasedContrast: contrast), background)
                        >= (contrast ? 3 : 1.4))
            }
        }
    }
    @Test func everyAppearanceMatchSelectsItsPalette() {
        for (name, dark, contrast): (NSAppearance.Name, Bool, Bool) in [
            (.aqua, false, false), (.darkAqua, true, false), (.accessibilityHighContrastAqua, false, true),
            (.accessibilityHighContrastDarkAqua, true, true),
        ] {
            let traits = MixPalette.appearanceTraits(for: name)
            #expect(traits.dark == dark && traits.increasedContrast == contrast)
        }
        #expect(MixPalette.appearanceTraits(for: nil) == (false, false))
    }
    @Test func dynamicColoursFollowTheAppearance() throws {
        for (name, dark, contrast): (NSAppearance.Name, Bool, Bool) in [
            (.aqua, false, false), (.darkAqua, true, false),
        ] {
            let appearance = try #require(NSAppearance(named: name))
            let pairs: [(NSColor, UInt32)] = [
                (
                    MixPalette.colour(forMaterialAt: 1),
                    MixPalette.hex(forMaterialAt: 1, dark: dark, increasedContrast: contrast)
                ), (MixPalette.missingBackground, MixPalette.missingHex(dark: dark, increasedContrast: contrast)),
                (MixPalette.cardStroke, MixPalette.cardStrokeHex(dark: dark, increasedContrast: contrast)),
            ]
            for (colour, expected) in pairs {
                var channels: [CGFloat] = []
                appearance.performAsCurrentDrawingAppearance {
                    if let rgb = colour.usingColorSpace(.sRGB) {
                        channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
                    }
                }
                #expect(channels.count == 3)
                for (value, shift) in zip(channels, [16, 8, 0]) {
                    #expect(
                        abs(value * 255 - CGFloat((expected >> shift) & 255)) <= 1,
                        "\(name): \(expected), channel \(shift)")
                }

            }
        }
        #expect(MixPalette.colour(forMaterialAt: 4) === MixPalette.colour(forMaterialAt: 0))
    }
    @Test("UI-M4: display option changes reach the model and palette") func uiM4IncreaseContrastSwitchesThePalette()
        async throws
    {
        let rig = try ShellRig(), model = AppModel(services: rig.services)
        await rig.ready(model)
        rig.system.increaseContrast = true; rig.system.send(.displayOptionsChanged)
        await shellEventually { model.increaseContrast }
        #expect(MixPalette.cardStrokeHex(dark: false, increasedContrast: true) == 0x6e6e73)
        #expect(MixPalette.hex(forMaterialAt: 5, dark: true, increasedContrast: false) == 0xf5a25d)
        model.terminated = true; model.systemTask?.cancel(); model.observationTask?.cancel()
    }
}
