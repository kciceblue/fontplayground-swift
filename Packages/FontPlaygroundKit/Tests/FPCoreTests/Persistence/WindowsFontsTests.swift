import FPCore
import Testing

struct WindowsFontsTests {
    @Test func fileTableCoversTTCIndexesAndSingleFaceStyles() {
        #expect(WindowsFonts.faceName(forFile: "ARIALBD.TTF", index: 0) == .init(family: "Arial", style: "Bold"))
        #expect(
            WindowsFonts.faceName(forFile: "msyhbd.ttc", index: 1) == .init(family: "Microsoft YaHei UI", style: "Bold")
        )
        #expect(WindowsFonts.faceName(forFile: "simsun.ttc", index: 1) == .init(family: "NSimSun"))
        #expect(WindowsFonts.faceName(forFile: "mingliu.ttc", index: 2) == .init(family: "MingLiU_HKSCS"))
        #expect(WindowsFonts.faceName(forFile: "gulim.ttc", index: 3) == .init(family: "DotumChe"))
        #expect(WindowsFonts.faceName(forFile: "meiryob.ttc", index: 3) == .init(family: "Meiryo", style: "Bold"))
        #expect(WindowsFonts.faceName(forFile: "simsun.ttc", index: 3) == nil)
        #expect(WindowsFonts.faceName(forFile: "unknown.ttf", index: 0) == nil)
        #expect(WindowsFonts.fileTable.count == 70)
    }

    @Test func replacementsMatchMainStyleAndKeepPreferredFamilyOrder() {
        let regular = fakeFace(cps("a"), path: "/SF.ttf", family: "SF Pro")
        let bold = fakeFace(cps("a"), path: "/SF-bold.ttf", family: "SF Pro", style: "Bold", weight: 700)
        let helvetica = fakeFace(cps("a"), path: "/Helvetica.ttf", family: "Helvetica Neue")
        let catalog = FaceCatalog([helvetica, regular, bold])
        #expect(WindowsFonts.replacements(forFamily: "Segoe UI", in: catalog, main: bold) == [bold, helvetica])
        #expect(WindowsFonts.replacements(forFamily: "Calibri", in: catalog, main: nil).isEmpty)
    }
}
