import Foundation
import Testing

struct RegistrationSafetyTests {
    private func violations(_ text: String, file: String) -> [SourceAudit.Violation] {
        let calls = try! NSRegularExpression(pattern: #"\bCTFontManager(?:Register|Unregister)[A-Za-z0-9_]*\s*\("#)
        return text.components(separatedBy: "\n").enumerated().flatMap { index, line in
            let tokens = Array(
                Set(
                    calls.matches(in: line, range: NSRange(line.startIndex..., in: line)).map {
                        String(line[Range($0.range, in: line)!])
                    }))
            let singular =
                line.contains("CTFontManagerRegisterFontsForURL(")
                || line.contains("CTFontManagerUnregisterFontsForURL(")
            let forbidden = [
                "CTFontManagerRegisterFontURLs(", "CTFontManagerRegisterFontDescriptors(",
                "CTFontManagerRegisterGraphicsFont(", ".persistent", ".user", ".session",
            ].contains { line.contains($0) }
            let allowed = file.hasPrefix("Tests/") && singular && line.contains(".process") && !forbidden
            return SourceAudit.violations(in: line, file: file, tokens: tokens, allowed: { _, _ in allowed ? 1 : 0 })
                .map { SourceAudit.Violation(file: $0.file, line: index + 1, token: $0.token) }
        }
    }
    @Test func install6Install7NoRegistrationInSourcesAndProcessScopeOnlyInTests() throws {
        let sources = try SourceAudit.swiftFiles(under: FixtureFonts.packageRoot.appendingPathComponent("Sources"))
        let tests = try SourceAudit.swiftFiles(under: FixtureFonts.packageRoot.appendingPathComponent("Tests"))
        #expect(sources.contains { $0.0 == "Sources/FPMacServices/Install/FontInstaller.swift" })
        #expect(tests.contains { $0.0 == "Tests/FPMacServicesTests/Support/FixtureFonts.swift" })
        for (file, text) in sources + tests { #expect(violations(text, file: file).isEmpty) }
    }
    @Test func scannerDetectsForbiddenRegistration() {
        let test = "Tests/FPMacServicesTests/Test.swift"
        #expect(violations("CTFontManagerRegisterFontURLs(urls, .process, true, nil)", file: test).count == 1)
        #expect(violations("CTFontManagerRegisterFontsForURL(url as CFURL, .user, &e)", file: test).count == 1)
        let allowed = "CTFontManagerRegisterFontsForURL(url as CFURL, .process, &e)"
        #expect(violations(allowed, file: test).isEmpty)
        #expect(violations(allowed, file: "Sources/X.swift").count == 1)
        #expect(violations("let o: FaceOrigin = .user", file: test).isEmpty)
        #expect(violations("let n = kCTFontManagerRegisteredFontsChangedNotification", file: "Sources/X.swift").isEmpty)
        #expect(violations("// " + allowed, file: "Sources/X.swift").isEmpty)
        #expect(violations("CTFontManagerUnregisterFontsForURL(url as CFURL, .session, nil)", file: test).count == 1)
    }
}
