import Foundation

enum Fixtures {
    static func url(_ relativePath: String) -> URL {
        let manager = FileManager.default
        if let root = ProcessInfo.processInfo.environment["FP_REPO_ROOT"] {
            return URL(fileURLWithPath: root).appendingPathComponent("spec/fixtures").appendingPathComponent(
                relativePath)
        }
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let fixtures = directory.appendingPathComponent("spec/fixtures")
            if manager.fileExists(atPath: fixtures.path) { return fixtures.appendingPathComponent(relativePath) }
            directory.deleteLastPathComponent()
        }
        preconditionFailure("Cannot find spec/fixtures above \(#filePath); set FP_REPO_ROOT")
    }

    static func load<T: Decodable>(_ type: T.Type, _ relativePath: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url(relativePath)))
    }
}
