import FPCore
import Foundation

struct FakeFileSystem: FileSystemProbe {
    var files: Set<String>
    var directories: Set<String>

    init(files: Set<String> = [], directories: Set<String> = []) {
        self.files = files; self.directories = directories
    }

    func kind(of path: String) -> FileKind {
        directories.contains(path) ? .directory : files.contains(path) ? .file : .missing
    }
}
