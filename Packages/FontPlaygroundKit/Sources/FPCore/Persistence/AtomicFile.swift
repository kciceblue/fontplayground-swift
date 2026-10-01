import Foundation

public enum AtomicFile {
    public static func write(_ data: Data, to path: String) throws {
        let destination = URL(fileURLWithPath: path)
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        let files = FileManager.default
        try files.createDirectory(at: parent, withIntermediateDirectories: true)
        guard files.createFile(atPath: temporary.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? files.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        // TOOLING-2: Foundation replaceItem differs across platforms; same-folder POSIX rename is atomic.
        guard rename(temporary.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
