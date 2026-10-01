import FPCore
import Foundation
import Testing

@testable import FPMacServices

struct CatalogReportTests {
    @Test func checkFindsEachProblem() {
        func snapshot(_ faces: [FaceRecord]) -> CatalogSnapshot {
            var result = CatalogSnapshot.empty; result.faces = faces; result.counts.faces = faces.count; return result
        }
        let dot = FaceRecord(path: "/A", family: ".Hidden", coverage: .empty, postscriptName: ".Hidden")
        #expect(!CatalogReport.check(snapshot([dot]), menuVisible: []).isEmpty)
        #expect(!CatalogReport.check(snapshot([]), menuVisible: ["PingFangSC-Regular"]).isEmpty)
        let normal = FaceRecord(path: "/B", family: "Clean", coverage: .empty, postscriptName: "Clean-Regular")
        var duplicate = normal; duplicate.path = "/C"
        #expect(
            CatalogReport.check(snapshot([normal, duplicate]), menuVisible: []).contains { $0.contains("Duplicate") })
        let asset = FaceRecord(
            path: "/System/Library/AssetsV2/PingFang.ttc", family: "PingFang SC", coverage: .empty,
            postscriptName: "PingFangSC-Regular")
        var privateFont = asset; privateFont.path = "/System/Library/PrivateFrameworks/PingFangUI.ttc"
        #expect(
            CatalogReport.check(snapshot([asset, privateFont]), menuVisible: []).contains {
                $0.contains("Private PingFang")
            })
        #expect(CatalogReport.check(snapshot([normal, asset]), menuVisible: ["PingFangSC-Regular"]).isEmpty)
        var forged = normal; forged.isForged = true
        var report = snapshot([forged]);
        report.annotations[forged.key] = .init(origin: .user, hiddenFromMenus: true, disabledInFontBook: true)
        #expect(
            CatalogReport.lines(for: report).first
                == "Clean\tRegular\tClean-Regular\tuser\thidden-from-menus,disabled,forged\t/B#0")
        #expect(
            CatalogReport.lines(for: report).last
                == "faces=1 files=0 hidden=0 duplicates=0 unreadable=0 skipped=0 disabled=0")
    }
}
