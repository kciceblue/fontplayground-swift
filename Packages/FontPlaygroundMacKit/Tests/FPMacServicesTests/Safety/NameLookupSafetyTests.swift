import Foundation
import Testing

struct NameLookupSafetyTests {
    private let tokens = [
        "CTFontCreateWithName(", "CTFontCreateWithNameAndOptions(",
        "CTFontDescriptorCreateWithNameAndSize(", "CTFontDescriptorCreateWithAttributes(",
        "CTFontDescriptorCreateMatchingFontDescriptors(", "CTFontDescriptorCreateMatchingFontDescriptor(",
        "CTFontDescriptorMatchFontDescriptorsWithProgressHandler(", "CTFontCollectionCreateWithFontDescriptors(",
        "NSFont(name:", "NSFontDescriptor(name:", ".font(withFamily:", "Font.custom(",
    ]
    private let allowed = [
        "Sources/FPMacServices/Rendering/LastResort.swift": ["CTFontDescriptorCreateWithNameAndSize(": 1],
        "Sources/FPMacServices/Downloads/CoreTextFontDownloader.swift": [
            "CTFontDescriptorCreateWithAttributes(": 1,
            "CTFontDescriptorMatchFontDescriptorsWithProgressHandler(": 1,
        ],
    ]

    private func allowance(file: String, token: String) -> Int { allowed[file]?[token] ?? 0 }

    @Test func sourcesContainNoNameLookups() throws {
        let files = try SourceAudit.swiftFiles(under: FixtureFonts.packageRoot.appendingPathComponent("Sources"))
        #expect(files.contains { $0.0 == "Sources/FPMacServices/Rendering/FontRenderer.swift" })
        for (path, text) in files {
            #expect(SourceAudit.violations(in: text, file: path, tokens: tokens, allowed: allowance).isEmpty)
        }
    }

    @Test func scannerDetectsForbiddenCall() {
        let source = "let f = CTFontCreateWithName(\"X\" as CFString, 12, nil)"
        let path = "Sources/FPMacServices/Catalog/X.swift"
        #expect(SourceAudit.violations(in: source, file: path, tokens: tokens, allowed: allowance).count == 1)
        #expect(SourceAudit.violations(in: "// " + source, file: path, tokens: tokens, allowed: allowance).isEmpty)
        let fallback = "let f = CTFontDescriptorCreateWithNameAndSize(\"LastResort\" as CFString, 0)"
        let approved = "Sources/FPMacServices/Rendering/LastResort.swift"
        #expect(SourceAudit.violations(in: fallback, file: approved, tokens: tokens, allowed: allowance).isEmpty)
        #expect(
            SourceAudit.violations(in: fallback + "\n" + fallback, file: approved, tokens: tokens, allowed: allowance)
                .count == 1)
    }
}
