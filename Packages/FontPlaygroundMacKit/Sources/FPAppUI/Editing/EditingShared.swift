// Types shared by the editing surfaces. Spec: docs/specs/ui-editing.md §S3. Keep identical to the spec.
import AppKit
import FPCore

/// What the recipe column or the preview's missing-characters note asks of the font picker (ui/requests.py).
public struct PickRequest: Equatable, Sendable {
    /// A `Language` id: what the picker lists, and what an added font is for ("any" for Any language).
    public var languageID: String
    /// The material being replaced (Change…); nil adds a font.
    public var replaceKey: FaceKey?

    public init(languageID: String, replaceKey: FaceKey? = nil) {
        self.languageID = languageID
        self.replaceKey = replaceKey
    }
}

/// The picker's candidate, drawn by the preview instead of the recipe until the picker closes.
public struct PreviewTrial: Equatable {
    public var mix: Mix
    public var banner: String

    public init(mix: Mix, banner: String) {
        self.mix = mix
        self.banner = banner
    }
}

/// A font the build flow just produced. The preview draws it until the recipe no longer matches it.
public struct BuiltFontPreview: Equatable {
    public var url: URL
    /// "Family Style" as written into the font.
    public var displayName: String
    /// What it was built from.
    public var spec: ForgeSpec

    public init(url: URL, displayName: String, spec: ForgeSpec) {
        self.url = url
        self.displayName = displayName
        self.spec = spec
    }

    /// Stale once anything that reaches the build changed (the sample text does not).
    public func isStale(for recipe: Recipe) -> Bool { recipe.forgeSpec() != spec }
}

/// UI-M4: text colours and boundaries remain legible in every system appearance.
@MainActor public enum MixPalette {
    private static let colours = (0..<4).map { index in
        dynamic(name: "FPMix\(index)") { dark, contrast in
            hex(forMaterialAt: index, dark: dark, increasedContrast: contrast)
        }
    }
    public static func colour(forMaterialAt index: Int) -> NSColor { colours[((index % 4) + 4) % 4] }
    public static let missingBackground = dynamic(name: "FPMissingBackground", value: missingHex)
    public static let cardStroke = dynamic(name: "FPCardStroke", value: cardStrokeHex)
    nonisolated public static func hex(forMaterialAt index: Int, dark: Bool, increasedContrast: Bool) -> UInt32 {
        let table: [[UInt32]] = [
            [0x1a6bd8, 0xb85209, 0x267a3a, 0x7c3aed],
            [0x6aa3ff, 0xf5a25d, 0x5cc27a, 0xc79bff],
            [0x0a4ea8, 0x8a3800, 0x1c6630, 0x5b21b6],
            [0xa8c8ff, 0xffc58f, 0x8fe3a8, 0xdcc6ff],
        ]
        return table[column(dark: dark, contrast: increasedContrast)][((index % 4) + 4) % 4]
    }
    nonisolated public static func missingHex(dark: Bool, increasedContrast: Bool) -> UInt32 {
        [0xffb3b3, 0x7a2e2e, 0xff8a8a, 0xa32b2b][column(dark: dark, contrast: increasedContrast)]
    }
    nonisolated public static func cardStrokeHex(dark: Bool, increasedContrast: Bool) -> UInt32 {
        [0xc6c6c8, 0x3a3a3c, 0x6e6e73, 0x98989d][column(dark: dark, contrast: increasedContrast)]
    }
    nonisolated private static func column(dark: Bool, contrast: Bool) -> Int { (dark ? 1 : 0) + (contrast ? 2 : 0) }
    // Accessibility names are bestMatch results, not constructible NSAppearance instances.
    nonisolated static func appearanceTraits(for match: NSAppearance.Name?) -> (dark: Bool, increasedContrast: Bool) {
        (
            match == .darkAqua || match == .accessibilityHighContrastDarkAqua,
            match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
        )
    }
    private static func dynamic(name: String, value: @escaping @Sendable (Bool, Bool) -> UInt32) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let traits = appearanceTraits(
                for: appearance.bestMatch(from: [
                    .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                ]))
            let hex = value(traits.dark, traits.increasedContrast)
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
}
