import CoreText
import FPCore
import Foundation
import Testing

@testable import FPMacServices

struct RenderPerformanceTests {
    @Test(.enabled(if: TestEnv.appleFonts)) func allSystemFacesColdAndWarm() throws {
        let urls = CTFontManagerCopyAvailableFontURLs() as? [URL] ?? []
        var byPath: [String: FaceRecord] = [:]
        for url in urls where url.isFileURL {
            guard byPath[url.path] == nil,
                let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
                fragment.hasPrefix("postscript-name=")
            else { continue }
            let name = String(fragment.dropFirst("postscript-name=".count))
            byPath[url.path] = FaceRecord(path: url.path, family: name, coverage: .empty, postscriptName: name)
        }
        #expect(!byPath.isEmpty)
        let requests = byPath.values.map { FaceRenderRequest(face: $0, pointSize: 20) }
        let renderer = FontRenderer()
        let coldStart = ContinuousClock.now
        for request in requests { _ = try renderer.font(for: request) }
        let cold = coldStart.duration(to: .now)
        let warmStart = ContinuousClock.now
        for request in requests { _ = try renderer.font(for: request) }
        let warm = warmStart.duration(to: .now)
        print("WP-402 rendering \(requests.count) registered files: cold=\(cold), warm=\(warm)")
        #expect(cold <= .seconds(1.5))
        #expect(warm <= .seconds(0.1))
    }
}
