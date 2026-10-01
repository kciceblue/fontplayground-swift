import FPCore
import Foundation
import Testing

struct AtomicFileTests {
    private func withTemporaryDirectory(_ operation: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(directory)
    }
    @Test func writesNewFile() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("new.fontrecipe")
            try AtomicFile.write(Data("new".utf8), to: path.path)
            #expect(try Data(contentsOf: path) == Data("new".utf8))
        }
    }
    @Test func replacesExistingFile() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("existing.fontrecipe")
            try Data("old".utf8).write(to: path)
            try AtomicFile.write(Data("replacement".utf8), to: path.path)
            #expect(try Data(contentsOf: path) == Data("replacement".utf8))
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["existing.fontrecipe"])
        }
    }
    @Test func createsMissingParentFolders() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("one/two/recipe.fontrecipe")
            try AtomicFile.write(Data("nested".utf8), to: path.path)
            #expect(try Data(contentsOf: path) == Data("nested".utf8))
        }
    }
    @Test func failureLeavesDestinationUntouched() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("parent-file")
            try Data("original".utf8).write(to: file)
            #expect(throws: (any Error).self) {
                try AtomicFile.write(Data(), to: file.appendingPathComponent("child").path)
            }
            #expect(try Data(contentsOf: file) == Data("original".utf8))
            let destination = directory.appendingPathComponent("existing-directory")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            let inside = destination.appendingPathComponent("kept")
            try Data("kept".utf8).write(to: inside)
            #expect(throws: (any Error).self) { try AtomicFile.write(Data(), to: destination.path) }
            #expect(try Data(contentsOf: inside) == Data("kept".utf8))
            #expect(
                try Set(FileManager.default.contentsOfDirectory(atPath: directory.path)) == [
                    "parent-file", "existing-directory",
                ])
        }
    }
}
