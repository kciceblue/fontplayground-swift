import AppKit
import CoreText
import FPCore
import FPMacServices
import Foundation
import Testing

@testable import FPAppUI

enum PickerTestFaces {
    static let latin = Array(UInt32(0x21)...0x7E) + Array(UInt32(0xC0)...0xC5)
    static let markers = Array("们这说国门来Aa1".unicodeScalars.map(\.value))
    static let han = Array(UInt32(0x4E00)..<0x4E00 + 2600) + markers
    static func make(
        _ family: String, points: [UInt32] = latin, style: String = "Regular", weight: Int = 400,
        path: String? = nil, names: [String] = [], extra: [String: Any] = [:]
    ) -> FaceRecord {
        let coverage = CodepointSet(points)
        var groups: [String: Int] = [:]
        for range in coverage.ranges {
            for cp in range.lowerBound...range.upperBound { groups[ScriptGroup.of(cp).rawValue, default: 0] += 1 }
        }
        var object: [String: Any] = [
            "path": path ?? "/picker/\(family)-\(style).ttf", "index": 0, "family": family,
            "style": style, "weight_class": weight, "local_names": names,
            "postscript_name": family.replacingOccurrences(of: " ", with: "") + "-" + style,
            "coverage": coverage.ranges.map { [$0.lowerBound, $0.upperBound] }, "group_counts": groups,
            "glyph_count": coverage.count + 1, "size": 1, "mtime": 1.0, "upem": 1000, "outline": "glyf",
        ]
        object.merge(extra) { _, new in new }
        return try! JSONDecoder().decode(FaceRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }
    static let s = make("Picker Simplified", points: han)
    static let h = make("Picker Plain Han", points: Array(UInt32(0x5600)..<0x5600 + 2600))
    static let l = make("Picker Latin")
    static let lb = make("Picker Latin", style: "Bold", weight: 700)
    static let z = make("Picker Zeta", names: ["测试黑体"])
    static let x = make("Picker Bitmap", extra: ["supported": false, "outline": "none"])
    static let catalog = [s, h, l, lb, z, x]
    @MainActor static func context(
        _ language: String = "any", main: FaceRecord? = nil, keys: Set<FaceKey> = [],
        suggestions: [FaceRecord] = [], replace: FaceKey? = nil, preferred: [String: String] = [:]
    ) -> PickerModel.Context {
        .init(
            request: .init(languageID: language, replaceKey: replace), main: main, recipeKeys: keys,
            suggestions: suggestions, preferredFamilies: preferred)
    }
    @MainActor static func model(
        _ language: String = "any", context: PickerModel.Context? = nil,
        catalog: [FaceRecord] = catalog, delay: Duration = .milliseconds(50),
        clock: any Clock<Duration> = ContinuousClock()
    ) -> PickerModel {
        let model = PickerModel(locale: Locale(identifier: "en_US"), candidateDelay: delay, clock: clock)
        model.open(context ?? self.context(language), catalog: catalog, status: CatalogStatus())
        return model
    }
    @MainActor static func rows(_ model: PickerModel) -> [String] {
        model.rows.map { row in
            switch row {
            case .header(let h): h.title;
            case .family(let f): f.family
            }
        }
    }
    @MainActor static func families(_ model: PickerModel) -> [String] {
        model.rows.compactMap(\.familyRow).map(\.family)
    }
}

@MainActor func pickerEventually(timeout: Duration = .seconds(5), _ predicate: () -> Bool) async throws {
    let end = ContinuousClock.now.advanced(by: timeout)
    while !predicate(), ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(5)) }
    #expect(predicate())
}

final class PickerTestRenderer: FontRendering, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let delay: TimeInterval
    let failurePath: String?
    var count: Int { lock.withLock { calls } }
    init(delay: TimeInterval = 0, failurePath: String? = nil) { self.delay = delay; self.failurePath = failurePath }
    func font(for request: FaceRenderRequest) throws -> RenderedFont {
        lock.withLock { calls += 1 }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        if request.face.path == failurePath { throw RenderError.fileMissing(path: request.face.path) }
        return RenderedFont(
            ctFont: CTFontCreateUIFontForLanguage(.system, request.pointSize, nil)!,
            fileURL: URL(fileURLWithPath: request.face.path), postscriptName: "PickerSystem",
            pointSize: request.pointSize)
    }
    func builtFont(at url: URL, pointSize: CGFloat) throws -> RenderedFont {
        throw RenderError.fileMissing(path: url.path)
    }
    func hasGlyph(for scalar: Unicode.Scalar, in font: RenderedFont) -> Bool { true }
    func missingScalars(in text: String, for font: RenderedFont) -> [Unicode.Scalar] { [] }
    func coverage(of font: RenderedFont) -> CodepointSet { .empty }
    func invalidate(path: String) {}
    func invalidateAll() {}
}
