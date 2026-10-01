import CryptoKit
import Darwin
import Foundation

public protocol InstallFileSystem: Sendable {
    func copyAndSync(from source: URL, to staged: URL) throws -> (size: Int64, sha256: String)
    func renameExclusive(_ from: URL, to: URL) throws
    func removeFile(_ url: URL) throws
    func writeAtomically(_ data: Data, to url: URL) throws
    func sha256(of url: URL) throws -> String
}

public struct PosixInstallFileSystem: InstallFileSystem {
    private let beforeRename: @Sendable (URL) throws -> Void
    public init() { beforeRename = { _ in } }
    init(beforeRename: @escaping @Sendable (URL) throws -> Void) { self.beforeRename = beforeRename }
    private func failure() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    private func create(_ url: URL) throws -> FileHandle {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw failure() }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    public func copyAndSync(from source: URL, to staged: URL) throws -> (size: Int64, sha256: String) {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try create(staged)
        var completed = false
        defer { try? output.close(); if !completed { try? removeFile(staged) } }
        var size: Int64 = 0
        var hash = SHA256()
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try output.write(contentsOf: chunk); hash.update(data: chunk); size += Int64(chunk.count)
        }
        guard fsync(output.fileDescriptor) == 0 else { throw failure() }
        try output.close()
        completed = true
        return (size, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    public func renameExclusive(_ from: URL, to: URL) throws {
        if renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 { return }
        guard errno == ENOTSUP else { throw failure() }
        // INSTALL-8: both paths are on the same volume; link preserves exclusive placement.
        guard link(from.path, to.path) == 0 else { throw failure() }
        if unlink(from.path) != 0 {
            let error = failure()
            _ = unlink(to.path)
            throw error
        }
    }
    public func removeFile(_ url: URL) throws {
        if unlink(url.path) != 0 && errno != ENOENT { throw failure() }
    }
    public func writeAtomically(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID()).tmp")
        let handle = try create(temporary)
        defer { try? handle.close(); try? removeFile(temporary) }
        try handle.write(contentsOf: data)
        guard fsync(handle.fileDescriptor) == 0 else { throw failure() }
        try handle.close()
        try beforeRename(temporary)
        guard rename(temporary.path, url.path) == 0 else { throw failure() }
    }
    public func sha256(of url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hash = SHA256()
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
