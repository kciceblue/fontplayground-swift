import FPCore
import Testing

struct SmartBasicsTests {
    @Test func defaultFaceMatchesMainItalicThenWeight() {
        let regular = fakeFace(cps("a"), path: "f.ttc", index: 0, family: "F")
        let bold = fakeFace(cps("a"), path: "f.ttc", index: 1, family: "F", style: "Bold", weight: 700)
        let italic = fakeFace(cps("a"), path: "f.ttc", index: 2, family: "F", style: "Italic", italic: true)
        let broken = fakeFace(
            cps("a"), path: "f.ttc", index: 3, family: "F", style: "Black", weight: 900, outline: .none)
        let faces = [bold, italic, regular, broken]
        #expect(Smart.defaultFace(faces, main: nil) == regular)
        #expect(Smart.defaultFace(faces, main: bold) == bold)
        var italicMain = bold; italicMain.italic = true
        #expect(Smart.defaultFace(faces, main: italicMain) == italic)
        #expect(Smart.defaultFace([broken], main: nil) == broken)
        #expect(Smart.defaultFace([], main: nil) == nil)
        #expect(Smart.defaultFace(faces, main: fakeFace(cps("a"), path: "m.ttf", weight: 900)) == bold)
        var tie = regular; tie.path = "tie.ttf"
        #expect(Smart.defaultFace([tie, regular], main: nil) == tie)
    }

    @Test func familyStylesOnePerStyleLightestFirst() {
        let own = fakeFace(cps("a"), path: "own.ttf", family: "Noto Sans")
        let other = fakeFace(cps("a"), path: "other.ttf", family: "Noto Sans")
        let bold = fakeFace(cps("a"), path: "bold.ttf", family: "Noto Sans", style: "Bold", weight: 700)
        let bad = fakeFace(cps("a"), path: "bad.ttf", family: "Noto Sans", style: "Black", weight: 900, outline: .none)
        #expect(Smart.familyStyles(of: own, in: FaceCatalog([other, bad, bold, own])) == [own, bold])
        #expect(Smart.familyStyles(of: own, in: FaceCatalog([])) == [own])
    }
}
