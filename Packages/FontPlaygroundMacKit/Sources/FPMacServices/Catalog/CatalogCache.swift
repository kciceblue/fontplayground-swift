import Darwin
import FPCore
import Foundation

struct CatalogCache: Sendable {
    static let schemaVersion = 1
    struct Failure: Codable, Sendable { var code: String; var message: String }
    struct Entry: Codable, Sendable {
        var size: Int64
        var mtime: Double
        var device: UInt64
        var inode: UInt64
        var faces: [FaceRecord]
        var error: Failure?
        init(file: DiscoveredFile, faces: [FaceRecord], error: Failure?) {
            size = file.stamp.size; mtime = file.stamp.mtime
            device = file.stamp.device; inode = file.stamp.inode
            self.faces = faces; self.error = error
        }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(size, forKey: .size); try c.encode(mtime, forKey: .mtime)
            try c.encode(device, forKey: .device); try c.encode(inode, forKey: .inode)
            try c.encode(faces, forKey: .faces); try c.encode(error, forKey: .error)
        }
    }
    var directory: URL
    var readerVersion: Int
    var entries: [String: Entry] = [:]
    var beforeRename: (@Sendable (URL) throws -> Void)?
    var url: URL { directory.appendingPathComponent("catalog-v\(Self.schemaVersion).json") }
    mutating func load() {
        entries = [:]
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        {
            if file.lastPathComponent.hasPrefix("catalog-v"), file.pathExtension == "json",
                file.lastPathComponent != url.lastPathComponent
            {
                try? FileManager.default.removeItem(at: file)
            }
        }
        guard let data = try? Data(contentsOf: url),
            let document = try? JSONDecoder().decode(LoadedDocument.self, from: data),
            document.format == "fontplayground-catalog-cache", document.schema == Self.schemaVersion,
            document.faceReaderVersion == readerVersion
        else { return }
        entries = document.entries.values
    }
    private struct LoadedDocument: Decodable {
        var format: String
        var schema: Int
        var faceReaderVersion: Int
        var entries: LossyEntries
        private enum CodingKeys: String, CodingKey {
            case format, schema, entries
            case faceReaderVersion = "face_reader_version"
        }
    }
    private struct LossyEntries: Decodable {
        var values: [String: Entry] = [:]
        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            for key in container.allKeys {
                guard let entry = try? container.decode(Entry.self, forKey: key), entry.mtime.isFinite,
                    entry.error?.code != "helper_failed", entry.error?.code != "no_faces"
                else { continue }
                values[key.stringValue] = entry
            }
        }
    }

    func hit(_ file: DiscoveredFile) -> Entry? {
        guard let entry = entries[file.path], entry.size == file.stamp.size,
            abs(entry.mtime - file.stamp.mtime) <= 1e-6
        else { return nil }
        return entry
    }
    mutating func put(_ file: DiscoveredFile, faces: [FaceRecord], error: Failure?) {
        entries.removeValue(forKey: file.path)
        guard error?.code != "helper_failed", error?.code != "no_faces",
            faces.allSatisfy({ $0.size == file.stamp.size })
        else { return }
        entries[file.path] = Entry(file: file, faces: faces, error: error)
    }
    func save() throws {
        struct Document: Encodable {
            var format = "fontplayground-catalog-cache"
            var schema = CatalogCache.schemaVersion
            var faceReaderVersion: Int
            var writtenAt: String
            var entries: [String: Entry]
            private enum CodingKeys: String, CodingKey {
                case format, schema, entries
                case faceReaderVersion = "face_reader_version", writtenAt = "written_at"
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID()).tmp")
        defer { try? FileManager.default.removeItem(at: temp) }
        let data = try JSONEncoder().encode(
            Document(
                faceReaderVersion: readerVersion,
                writtenAt: ISO8601DateFormatter().string(from: Date()), entries: entries))
        guard FileManager.default.createFile(atPath: temp.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: temp)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() } catch {
            try? handle.close(); throw error
        }
        try beforeRename?(temp)
        guard rename(temp.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
