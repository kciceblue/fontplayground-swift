import FPCore
import Foundation

func cps(_ text: String) -> CodepointSet { CodepointSet(scalarsOf: text) }

func fakeFace(
    _ coverage: CodepointSet, path: String = "fake.ttf", index: Int = 0, family: String = "Fake",
    style: String = "Regular", upem: Int = 1000, weight: Int = 400, outline: FaceRecord.Outline = .glyf,
    axes: [FaceRecord.Axis] = [], embedding: FaceRecord.Embedding = .installable, hasColor: Bool = false,
    italic: Bool = false, glyphCount: Int? = nil, postscriptName: String? = nil, hidden: Bool = false,
    suspiciousCoverage: Bool = false, unshaped: CodepointSet = .empty,
    shapesGroups: Set<ScriptGroup>? = nil, aat: FaceRecord.AATFlags = .init()
) -> FaceRecord {
    FaceRecord(
        path: path, index: index, family: family, style: style, coverage: coverage, unshaped: unshaped,
        weightClass: weight, italic: italic, upem: upem, glyphCount: glyphCount ?? coverage.count + 1,
        outline: outline, axes: axes, hasColor: hasColor, embedding: embedding, size: 1, mtime: 1.0,
        postscriptName: postscriptName, hidden: hidden, suspiciousCoverage: suspiciousCoverage,
        shapesGroups: shapesGroups, aat: aat)
}

enum TestFaces {
    static let a = fakeFace(cps("abc1,"), path: "/fixtures/A.ttf", family: "Fixture A")
    static let b = fakeFace(
        cps("ab漢，"), path: "/fixtures/B.otf", family: "Fixture B", style: "Bold", weight: 700, outline: .cff)
    static let c = fakeFace(
        cps("a→Ω"), path: "/fixtures/C.ttf", family: "Fixture C", upem: 2048, embedding: .restricted)
    static var all: [FaceRecord] { [a, b, c] }
}
