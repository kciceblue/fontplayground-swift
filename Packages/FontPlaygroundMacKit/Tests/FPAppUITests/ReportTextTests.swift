import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct ReportTextTests {
    @Test func rendersEverySection() {
        var report = ForgeReport(
            outputPath: "/temporary/not-shown.ttf", postscriptName: "TestMix-Regular", fullName: "Test Mix Regular",
            totalCodepoints: 7, totalGlyphs: 8,
            materials: [
                .init(name: "Fixture A Regular", path: "/A", codepoints: 5, groups: ["latin"]),
                .init(
                    name: "Fixture B Bold", path: "/B", codepoints: 2, groups: ["han", "cjk_symbols"],
                    warnings: ["Made bolder synthetically (+300)"]),
            ],
            licenceNotes: [
                .init(
                    licenceClass: "apple-sla", materialIndexes: [1],
                    text: "Bundled with macOS: licensed for use on this Mac only; do not distribute the forged font.")
            ], warnings: ["w1", "w2"], durationSeconds: 2.34)
        #expect(
            ReportText.render(report) == """
                Font: Test Mix Regular (PostScript name TestMix-Regular)
                Characters: 7   Glyphs: 8
                Built in 2.3 s

                Fixture A Regular: 5 characters  [Latin]
                Fixture B Bold: 2 characters  [Han, CJK symbols & fullwidth]
                    warning: Made bolder synthetically (+300)

                Licence:
                  - Bundled with macOS: licensed for use on this Mac only; do not distribute the forged font. (Fixture B Bold)

                Warnings:
                  - w1
                  - w2
                """)
        report.warnings = []; report.licenceNotes = []; report.durationSeconds = nil; report.materials[1].warnings = []
        let minimal = ReportText.render(report)
        #expect(!minimal.contains("Built in") && !minimal.contains("Licence:") && !minimal.contains("Warnings:"))
        #expect(minimal.hasSuffix("Fixture B Bold: 2 characters  [Han, CJK symbols & fullwidth]"))
        #expect(ReportText.failure(message: "m", detail: "") == "m")
        #expect(ReportText.failure(message: "m", detail: "Traceback…") == "m\n\nTraceback…")
    }
}
