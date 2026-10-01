import AppKit
import CoreText
import FPCore
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct PreviewRunsTests {
    var a: FaceRecord { ShellFaces.make(text: "abc1, ") }
    var b: FaceRecord { ShellFaces.make("B", path: "/B.otf", text: "ab漢， ") }
    @Test func aRuleDecidesWhoDrawsASharedCharacter() {
        let mix = Mix(fonts: [.init(face: a), .init(face: b)], rules: [.latin: 1])
        #expect(PreviewRuns.sources("ab"[...].unicodeScalars, source: mix.source) == [1, 1])
    }
    @Test func spaceTakesTheRunBefore() {
        let mix = Mix(fonts: [.init(face: a), .init(face: b, scale: 0.5)])
        #expect(PreviewRuns.sources(" 漢 a"[...].unicodeScalars, source: mix.source) == [1, 1, 1, 0])
        #expect(PreviewRuns.sources(" 한 "[...].unicodeScalars, source: mix.source) == [0, nil, 0])
        #expect(PreviewRuns.sources(" ​"[...].unicodeScalars, source: mix.source) == [0, 0])
    }
    @Test func astralScalarsDoNotShiftLaterRuns() {
        let mix = Mix(fonts: [.init(face: a), .init(face: b)]), runs = PreviewRuns.runs("𠀀ab漢"[...], source: mix.source)
        #expect(
            runs.map(\.range) == [
                NSRange(location: 0, length: 2), NSRange(location: 2, length: 2), NSRange(location: 4, length: 1),
            ])
        #expect(runs.map(\.source) == [nil, 0, 1])
        #expect(
            PreviewConfiguration(mode: .mix(mix), pointSize: 30, colourByFont: false).missingScalars(in: "𠀀ab漢").map(
                String.init) == ["𠀀"])
    }
}
