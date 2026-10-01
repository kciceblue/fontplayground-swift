import FPCore
import Foundation

public struct AppNotice: Identifiable, Equatable {
    public enum Kind: Equatable {
        case unresolvedFonts, fontsUnavailable, damagedRecipe, engineUnavailable, settingsIssues, restorationIssues,
            fileDropped, imported,
            importFailed, autosaveFailed
    }
    public struct Replacement: Equatable {
        public var missing: FaceKey
        public var missingName: String
        public var replacement: FaceKey
        public var replacementName: String
        public init(missing: FaceKey, missingName: String, replacement: FaceKey, replacementName: String) {
            self.missing = missing; self.missingName = missingName; self.replacement = replacement;
            self.replacementName = replacementName
        }
    }
    public let id: UUID
    public var kind: Kind
    public var text: String
    public var revealURL: URL?
    public var replacements: [Replacement]
    public init(id: UUID = UUID(), kind: Kind, text: String, revealURL: URL? = nil, replacements: [Replacement] = []) {
        self.id = id; self.kind = kind; self.text = text; self.revealURL = revealURL; self.replacements = replacements
    }
}
