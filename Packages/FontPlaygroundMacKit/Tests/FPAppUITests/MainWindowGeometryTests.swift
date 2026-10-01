import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct MainWindowGeometryTests {
    @Test("UI-4: initial frame fits the visible screen") func ui4InitialFrameFitsTheVisibleScreen() {
        let rows: [(CGRect, CGRect)] = [
            (CGRect(x: 0, y: 85, width: 1352, height: 764), CGRect(x: 68, y: 123, width: 1216, height: 687)),
            (CGRect(x: 0, y: 0, width: 2560, height: 1415), CGRect(x: 640, y: 283, width: 1280, height: 848)),
            (CGRect(x: 0, y: 0, width: 1024, height: 700), CGRect(x: 51, y: 35, width: 921, height: 630)),
            (CGRect(x: -1440, y: 0, width: 1440, height: 875), CGRect(x: -1360, y: 44, width: 1280, height: 787)),
            (CGRect(x: 0, y: 0, width: 600, height: 400), CGRect(x: 0, y: -132, width: 640, height: 532)),
        ]
        for (visible, expected) in rows {
            let result = MainWindowGeometry.initialFrame(visibleFrame: visible, chromeHeight: 52);
            #expect(result == expected && result.maxY <= visible.maxY)
        }
    }
    @Test("CRIT-8: minimum width allows half-screen tiling") func crit8MinimumWidthAllowsHalfScreenTiling() {
        #expect(MainWindowGeometry.minContentSize.width <= 660)
        #expect(260 + 360 + 20 <= MainWindowGeometry.minContentSize.width)
    }
}
