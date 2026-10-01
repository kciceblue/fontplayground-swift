import Foundation
import Testing

@testable import FPCore

@Suite("Migration documentation") struct MigrationDocTests {
    @Test("CRIT-3: documented Mac equivalents match the import model")
    func crit3DocTableMatchesEquivalents() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let text = try String(
            contentsOf: root.appendingPathComponent("docs/user/migrating-from-windows.md"), encoding: .utf8)
        let table = try #require(text.components(separatedBy: "## Windows fonts and their Mac equivalents\n").last)
            .components(separatedBy: "\n## ")[0]
        var seen: Set<String> = []
        for line in table.components(separatedBy: .newlines) where line.hasPrefix("| ") {
            let columns = line.split(separator: "|", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count == 3, columns[0] != "On Windows", columns[0] != "Calibri",
                columns[1] != "the same fonts"
            else { continue }
            let windows = columns[0].components(separatedBy: ", ")
            let mac = columns[1].components(separatedBy: ", ")
            for family in windows {
                #expect(seen.insert(family).inserted)
                #expect(WindowsFonts.equivalents[family] == mac)
            }
        }
        #expect(seen == Set(WindowsFonts.equivalents.keys))
    }
}
