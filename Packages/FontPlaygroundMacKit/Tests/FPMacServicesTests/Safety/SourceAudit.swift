import Foundation

enum SourceAudit {
    struct Violation: Equatable { var file: String; var line: Int; var token: String }
    static func violations(
        in text: String, file: String, tokens: [String], allowed: (String, String) -> Int
    ) -> [Violation] {
        var counts: [String: Int] = [:]
        var result: [Violation] = []
        for (line, text) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }
            for token in tokens {
                let occurrences = text.components(separatedBy: token).count - 1
                for _ in 0..<occurrences {
                    counts[token, default: 0] += 1
                    if counts[token, default: 0] > allowed(file, token) {
                        result.append(.init(file: file, line: line + 1, token: token))
                    }
                }
            }
        }
        return result
    }
    static func swiftFiles(under root: URL) throws -> [(String, String)] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [(String, String)] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let relative = String(file.path.dropFirst(FixtureFonts.packageRoot.path.count + 1))
            guard !relative.hasPrefix("Tests/FPMacServicesTests/Safety/") else { continue }
            result.append((relative, try String(contentsOf: file, encoding: .utf8)))
        }
        return result.sorted { $0.0 < $1.0 }
    }
}
