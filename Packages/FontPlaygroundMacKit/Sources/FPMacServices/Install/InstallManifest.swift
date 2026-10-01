import Foundation

struct InstallManifest: Codable {
    struct Entry: Codable {
        var fileName: String
        var family: String
        var style: String
        var fullName: String
        var postscriptName: String
        var sha256: String
        var size: Int64
        var installedAt: Date
        private enum CodingKeys: String, CodingKey {
            case fileName = "file_name", family, style, fullName = "full_name", postscriptName = "postscript_name"
            case sha256, size, installedAt = "installed_at"
        }
        init(_ font: InstalledFont) {
            fileName = font.fileURL.lastPathComponent; family = font.family; style = font.style;
            fullName = font.fullName
            postscriptName = font.postscriptName; sha256 = font.sha256; size = font.size; installedAt = font.installedAt
        }
        func font(in folder: URL) -> InstalledFont? {
            guard !fileName.isEmpty, fileName != ".", fileName != "..", !fileName.contains("/") else { return nil }
            return .init(
                fileURL: folder.appendingPathComponent(fileName), family: family, style: style, fullName: fullName,
                postscriptName: postscriptName, sha256: sha256, size: size, installedAt: installedAt)
        }
    }
    var format = "fontplayground-installed-fonts"
    var version = 1
    var fonts: [Entry] = []
    static func read(_ url: URL, now: Date) throws -> InstallManifest {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let data = try Data(contentsOf: url)
        // A future manifest remains untouched even if its entry schema has changed.
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = object["version"] as? Int, version > 1
        {
            throw InstallError.manifestUnsupported
        }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(InstallManifest.self, from: data)
            guard manifest.format == "fontplayground-installed-fonts", manifest.version == 1 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return manifest
        } catch {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd-HHmmss"
            var backup = url.appendingPathExtension("corrupt-\(formatter.string(from: now))")
            if FileManager.default.fileExists(atPath: backup.path) {
                backup = backup.appendingPathExtension(UUID().uuidString)
            }
            try FileManager.default.moveItem(at: url, to: backup)
            return .init()
        }
    }
    func write(to url: URL, fileSystem: any InstallFileSystem) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try fileSystem.writeAtomically(encoder.encode(self), to: url)
    }
}
