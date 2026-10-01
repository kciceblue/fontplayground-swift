import AppKit
import CoreText
import FPCore
import FPMacServices
import Foundation
import Testing

@testable import FPAppUI

@Suite(.serialized) @MainActor struct PickerPerformanceTests {
    private var factor: Double { Double(ProcessInfo.processInfo.environment["FP_PERF_FACTOR"] ?? "1") ?? 1 }
    private func milliseconds(_ start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
    }
    private func median(_ times: [Double]) -> Double { times.sorted()[times.count / 2] }
    private func faces(_ count: Int) -> [FaceRecord] {
        let template = PickerTestFaces.make("Template", points: PickerTestFaces.latin + PickerTestFaces.han)
        return (0..<count).map { i in
            var face = template; face.family = String(format: "Family %04d", i % 420)
            face.path = "/picker/performance/\(i).ttf"; face.postscriptName = "Performance-\(i)"
            face.weightClass = 400 + (i / 420) * 100; face.style = "Style \(i / 420)"
            return face
        }
    }
    @Test func rowsBuildWithin25ms() {
        let catalog = faces(1200), index = PickerRows.Index(catalog), context = PickerTestFaces.context()
        for (id, query) in [(LanguageID.any, ""), (.chineseSimplified, "12")] {
            var samples: [Double] = []
            for run in 0..<6 {
                let start = ContinuousClock.now
                let result = PickerRows.build(
                    catalog: catalog, language: Languages.language(id), query: query,
                    context: context, showsUnshapable: false, locale: .init(identifier: "en_US"), index: index)
                #expect(result.listedFamilyCount == 420)
                if run > 0 { samples.append(milliseconds(start)) }
            }
            let result = median(samples)
            print("WP503 rows \(id.rawValue): median \(result) ms (1200 faces / 420 families)")
            #expect(result <= 25 * factor)
        }
    }
    @Test func openWithin150ms() async throws {
        let temp = try ShellTempDirectory(), renderer = try PickerURLRenderer(), catalog = faces(420)
        var samples: [Double] = []
        for run in 0..<6 {
            let app = AppModel(services: .testing(root: temp.url, defaults: temp.defaults, renderer: renderer))
            app.catalogFaces = catalog
            let start = ContinuousClock.now
            app.openPicker(.init(languageID: "any"))
            let rig = PickerTableRig(model: app.picker, renderer: renderer)
            rig.draw()
            if run > 0 { samples.append(milliseconds(start)) }
            #expect(rig.table.numberOfRows == 421)
            app.cancelPicker(); rig.cache.removeAll(); rig.window.close()
            await Task.yield()
        }
        let result = median(samples)
        print("WP503 open: median \(result) ms (420 families, 360 x 640)")
        #expect(result <= 150 * factor)
    }
    @Test func scrollWithoutDroppedFrames() async throws {
        let renderer = try PickerURLRenderer(), catalog = faces(420)
        let rig = PickerTableRig(model: PickerTestFaces.model(catalog: catalog), renderer: renderer)
        defer { rig.cache.removeAll(); rig.window.close() }
        rig.draw()
        try await Task.sleep(for: .milliseconds(20))
        var samples: [Double] = [], firstVisible: [FaceKey: Int] = [:], examined: Set<FaceKey> = []
        var y: CGFloat = 0, step = 0
        let end = max(0, rig.table.bounds.height - rig.scroll.contentSize.height)
        repeat {
            let start = ContinuousClock.now
            rig.scroll.contentView.scroll(to: CGPoint(x: 0, y: min(y, end)))
            rig.scroll.reflectScrolledClipView(rig.scroll.contentView); rig.draw()
            samples.append(milliseconds(start))
            let visible = rig.table.rows(in: rig.table.visibleRect)
            if visible.location != NSNotFound {
                for index in visible.location..<min(rig.model.rows.count, NSMaxRange(visible)) {
                    guard let face = rig.model.rows[index].familyRow?.face else { continue }
                    examined.insert(face.key)
                    if firstVisible[face.key] == nil { firstVisible[face.key] = step }
                    if step - firstVisible[face.key]! >= 1 && !renderer.failed.contains(face.key) {
                        let cell = rig.table.view(atColumn: 0, row: index, makeIfNecessary: true) as? FontRowCellView
                        #expect(cell?.drewInOwnFace == true)
                    }
                }
            }
            step += 1; y += rig.scroll.contentSize.height / 2
            // Let queued font batches run between display frames, as they do during a trackpad gesture. Yield for one
            // frame rather than sleep: the CI runner stretched a 16 ms sleep to over 100 ms, so every sample started on
            // an idle, clocked-down core and p95 doubled (docs/testing.md §3).
            let frame = ContinuousClock.now.advanced(by: .milliseconds(16))
            while ContinuousClock.now < frame { await Task.yield() }
        } while y < end + rig.scroll.contentSize.height / 2
        #expect(examined.count == 420)
        let sorted = samples.sorted(), p95 = sorted[Int(Double(sorted.count - 1) * 0.95)], maximum = sorted.last!
        print(
            "WP503 scroll: p95 \(p95) ms, max \(maximum) ms, \(samples.count) half-viewport steps / \(examined.count) families"
        )
        #expect(p95 <= 16.7 * factor && maximum <= 33 * factor)
    }
}

private final class PickerURLRenderer: FontRendering, @unchecked Sendable {
    private let urls: [URL]
    private let lock = NSLock()
    private var descriptors: [URL: CTFontDescriptor] = [:]
    private var failures: Set<FaceKey> = []
    var failed: Set<FaceKey> { lock.withLock { failures } }
    init() throws {
        urls = (CTFontManagerCopyAvailableFontURLs() as? [URL] ?? []).filter {
            $0.isFileURL && FileManager.default.fileExists(atPath: $0.path)
        }
        try #require(!urls.isEmpty)
    }
    func font(for request: FaceRenderRequest) throws -> RenderedFont {
        let index = Int(URL(fileURLWithPath: request.face.path).deletingPathExtension().lastPathComponent) ?? 0
        let url = urls[index % urls.count]
        return try lock.withLock {
            let descriptor: CTFontDescriptor
            if let cached = descriptors[url] {
                descriptor = cached
            } else if let first = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?
                .first
            {
                descriptor = CTFontDescriptorCreateCopyWithAttributes(
                    first,
                    [kCTFontCascadeListAttribute: [LastResort.shared.descriptor]] as CFDictionary)
                descriptors[url] = descriptor
            } else {
                failures.insert(request.face.key); throw RenderError.unreadable(path: url.path)
            }
            let font = CTFontCreateWithFontDescriptor(descriptor, request.pointSize, nil)
            return RenderedFont(
                ctFont: font, fileURL: url, postscriptName: CTFontCopyPostScriptName(font) as String,
                pointSize: request.pointSize)
        }
    }
    func builtFont(at url: URL, pointSize: CGFloat) throws -> RenderedFont {
        throw RenderError.unreadable(path: url.path)
    }
    func hasGlyph(for scalar: Unicode.Scalar, in font: RenderedFont) -> Bool { true }
    func missingScalars(in text: String, for font: RenderedFont) -> [Unicode.Scalar] { [] }
    func coverage(of font: RenderedFont) -> CodepointSet { .empty }
    func invalidate(path: String) {}
    func invalidateAll() {}
}
