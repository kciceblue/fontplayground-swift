import AppKit
import CoreText
import FPCore
import FPMacServices
import Foundation

@testable import FPAppUI

enum RecipeTestFaces {
    static func make(
        _ file: String, family: String, chars: String, style: String = "Regular", weight: Int = 400,
        fields: [String: Any] = [:]
    ) throws -> FaceRecord {
        let scalars = Set(chars.unicodeScalars.map(\.value)).sorted()
        var counts: [String: Int] = [:]
        for scalar in scalars { counts[ScriptGroup.of(scalar).rawValue, default: 0] += 1 }
        var object: [String: Any] = [
            "path": "/virtual/recipe/" + file, "index": 0, "family": family, "style": style,
            "weight_class": weight, "coverage": scalars.map { [$0, $0] }, "group_counts": counts,
            "size": 1, "mtime": 1, "postscript_name": family.replacingOccurrences(of: " ", with: "") + "-" + style,
        ]
        object.merge(fields) { _, new in new }
        return try JSONDecoder().decode(FaceRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }
    static func basic() throws -> [FaceRecord] {
        [
            try make("A.ttf", family: "Fixture A", chars: "abc1,"),
            try make("B.ttf", family: "Fixture B", chars: "ab漢，", style: "Bold", weight: 700),
            try make("C.ttf", family: "Fixture C", chars: "a→Ω", fields: ["embedding": "restricted"]),
            try make(
                "V.ttf", family: "Fixture V", chars: "ab",
                fields: ["axes": [["tag": "wght", "min": 100, "default": 400, "max": 900]]]),
        ]
    }
    static func coveredNames() throws -> [FaceRecord] {
        [
            try make("A.ttf", family: "Fixture A", chars: "abc1,Fixture A"),
            try make(
                "B.ttf", family: "Fixture B", chars: "ab漢，Fixture B汉字体", style: "Bold", weight: 700,
                fields: ["local_names": ["汉字体"]]),
        ]
    }
    static func geeza(shapes: [String] = []) throws -> FaceRecord {
        let chars = (0x0627...0x0632).compactMap(Unicode.Scalar.init).map(String.init).joined()
        return try make(
            "G.ttf", family: "Geeza Pro", chars: chars,
            fields: [
                "aat": ["morx": true],
                "ot_scripts": ["gsub": []], "shapes_groups": shapes,
                "unshaped": shapes.isEmpty ? [[0x0627, 0x0632]] : [],
            ])
    }
}
@MainActor struct RecipeTestRig {
    let root: URL
    let suite: String
    let defaults: UserDefaults
    let renderer = RecipeTestRenderer()
    let model: AppModel
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("recipe-ui-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "fp-test-recipe-\(UUID())"; defaults = UserDefaults(suiteName: suite)!
        model = AppModel(
            services: .testing(root: root, defaults: defaults, renderer: renderer, catalog: ShellFakeCatalog()))
    }
    func cleanup() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    func load(_ faces: [FaceRecord], catalog: [FaceRecord]? = nil, sample: String = "") {
        model.catalogFaces = catalog ?? faces
        model.edit { recipe in
            recipe = Recipe(); recipe.setSampleText(sample); for face in faces { recipe.add(face) }
        }
    }
    var state: RecipeColumnState {
        .make(recipe: model.recipe, catalog: model.catalogFaces, isBuilding: model.isBuilding)
    }
}
final class RecipeTestRenderer: FontRendering, @unchecked Sendable {
    private let lock = NSLock()
    private var requested: [FaceKey] = []
    var calls: [FaceKey] { lock.withLock { requested } }
    func font(for request: FaceRenderRequest) throws -> RenderedFont {
        lock.withLock { requested.append(request.face.key) }
        return RenderedFont(
            ctFont: CTFontCreateUIFontForLanguage(.system, request.pointSize, nil)!,
            fileURL: URL(fileURLWithPath: request.face.path), postscriptName: "RecipeSystem",
            pointSize: request.pointSize)
    }
    func builtFont(at url: URL, pointSize: CGFloat) throws -> RenderedFont {
        RenderedFont(
            ctFont: CTFontCreateUIFontForLanguage(.system, pointSize, nil)!, fileURL: url,
            postscriptName: "RecipeSystem", pointSize: pointSize)
    }
    func hasGlyph(for scalar: Unicode.Scalar, in font: RenderedFont) -> Bool { true }
    func missingScalars(in text: String, for font: RenderedFont) -> [Unicode.Scalar] { [] }
    func coverage(of font: RenderedFont) -> CodepointSet { .empty }
    func invalidate(path: String) {}
    func invalidateAll() {}
}
