import Foundation

public enum FileKind: Sendable, Equatable { case file, directory, missing }

public protocol FileSystemProbe: Sendable {
    func kind(of path: String) -> FileKind
}

public struct LocalFileSystem: FileSystemProbe {
    public init() {}

    public func kind(of path: String) -> FileKind {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory) else { return .missing }
        return directory.boolValue ? .directory : .file
    }
}
