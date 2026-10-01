import FPCore
import FPEngineClient
import Foundation
import Testing

@testable import fpctl

struct OutputTests {
    @Test func reportAndProgressKeepPlainWordsAndUnknownGroups() {
        let capture = CapturedOutput()
        capture.output.report(
            .init(
                outputPath: "/tmp/out.ttf", familyName: "Mix", styleName: "Regular", postscriptName: "Mix-Regular",
                fullName: "Mix Regular", totalCodepoints: 42, totalGlyphs: 43,
                materials: [
                    .init(
                        name: "A Regular", path: "/a.ttf", codepoints: 42, groups: ["latin", "future"],
                        warnings: ["material warning"])
                ],
                licenceNotes: [.init(licenceClass: "unknown", materialIndexes: [0], text: "Check the source licence.")],
                warnings: ["global warning"], durationSeconds: 1.25))
        #expect(
            capture.out == """
                Output: /tmp/out.ttf
                Font: Mix Regular (PostScript Mix-Regular)
                Characters: 42   Glyphs: 43

                A Regular: 42 characters  [Latin, future]
                    warning: material warning

                Warnings:
                  - global warning

                Licence:
                  - Check the source licence.
                Built in 1.2 s.
                """)
        for (stage, fraction, expected) in [
            (EngineStage.validate, 0.0, "[  0%] Checking the fonts…"), (.merge, 0.7, "[ 70%] Combining the fonts…"),
            (.prepare, 0.05, "[  5%] Preparing A Regular…"), (.done, 1, "[100%] Done."),
        ] {
            let output = CapturedOutput()
            output.output.progress(
                .init(stage: stage, fraction: fraction, materialIndex: 0), materialNames: ["A Regular"])
            #expect(output.err == expected)
        }
    }
}
