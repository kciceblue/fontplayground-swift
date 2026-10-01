import Foundation

public enum FolderCheck {
    public enum Failure: Error, Sendable, Equatable { case empty, windowsPath, notAbsolute, missing, notADirectory }
    public struct Accepted: Sendable, Equatable {
        public let path: String
        public let insideApplicationBundle: Bool
        public init(path: String, insideApplicationBundle: Bool) {
            self.path = path; self.insideApplicationBundle = insideApplicationBundle
        }
    }

    public static func check(_ raw: String, using probe: any FileSystemProbe) -> Result<Accepted, Failure> {
        let trimmed = Naming.cleanName(raw)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard !looksWindows(trimmed) else { return .failure(.windowsPath) }
        guard trimmed.hasPrefix("/") else { return .failure(.notAbsolute) }
        let path = URL(fileURLWithPath: trimmed).standardized.path
        switch probe.kind(of: path) {
        case .missing: return .failure(.missing)
        case .file: return .failure(.notADirectory)
        case .directory: return .success(Accepted(path: path, insideApplicationBundle: insideApplicationBundle(path)))
        }
    }

    static func looksWindows(_ path: String) -> Bool {
        if path.contains("\\") { return true }
        let scalars = Array(path.unicodeScalars.prefix(2))
        return scalars.count == 2 && scalars[1] == ":"
            && ((65...90).contains(scalars[0].value) || (97...122).contains(scalars[0].value))
    }
    static func insideApplicationBundle(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0.hasSuffix(".app") }
    }
}
