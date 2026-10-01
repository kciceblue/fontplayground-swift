import FPCore
import FPMacServices
import Foundation
import Testing

struct FileNameAgreementTests {
    @Test func installerAndSaveUseTheSameStem() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("spec/fixtures/naming/family-names.json"))
        let document = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try #require(document["file_stem"] as? [[String]])
        var names: [(String, String)] = [(".Hidden", "Regular"), ("  ", ""), ("A/B", "C:D")]
        for item in cases {
            let family = item[0], style = item[1]
            if !family.hasPrefix(".") { names.append((family, style)) }
        }
        #expect(names.count > 3)
        for (family, style) in names {
            #expect(
                InstallFileName.stem(family: family, style: style) + ".ttf"
                    == Naming.fileName(family: family, style: style))
        }
    }
}
