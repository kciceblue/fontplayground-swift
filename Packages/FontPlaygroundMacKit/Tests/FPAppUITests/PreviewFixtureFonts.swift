import AppKit
import CoreText
import FPCore
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor final class PreviewFixtureFonts {
    private static var cachedFontData: [String: Data]?
    let temp: ShellTempDirectory
    let renderer = FontRenderer()
    var root: URL { temp.url }
    var a: FaceRecord { face("A", "Fixture A", "abc1, ") }
    var b: FaceRecord {
        var f = face("B", "Fixture B", "ab漢， ", style: "Bold", ext: "otf"); f.weightClass = 700; f.outline = .cff;
        return f
    }
    var c: FaceRecord { var f = face("C", "Fixture C", "a→Ω "); f.upem = 2048; return f }
    var v: FaceRecord {
        var f = face("V", "Fixture V", "ab "); f.axes = [.init(tag: "wght", min: 100, default: 400, max: 900)];
        f.isVariable = true; return f
    }
    var r: FaceRecord { face("R", "Fixture Arabic", arabicText) }
    var r0: FaceRecord { face("R0", "Fixture Arabic Plain", arabicText) }
    private var arabicText: String {
        "ab ابدغ" + String(String.UnicodeScalarView((0xFE8D...0xFED0).compactMap(Unicode.Scalar.init)))
    }
    init() throws {
        temp = try ShellTempDirectory()
        if let cached = Self.cachedFontData {
            for (name, data) in cached { try data.write(to: root.appending(path: name), options: .atomic) }
            return
        }
        let process = Process();
        process.executableURL = URL(
            fileURLWithPath: try #require(ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"]))
        process.arguments = ["-c", Self.script, root.path]
        let pipe = Pipe(); process.standardError = pipe; process.standardOutput = pipe
        try process.run(); let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ShellTestError(String(decoding: output, as: UTF8.self)) }
        // Generate once; each test still owns distinct files so registration, invalidation and deletion are isolated.
        Self.cachedFontData = try Dictionary(
            uniqueKeysWithValues: ["A.ttf", "B.otf", "C.ttf", "V.ttf", "R.ttf", "R0.ttf"].map {
                ($0, try Data(contentsOf: root.appending(path: $0)))
            })
    }
    private func face(_ file: String, _ family: String, _ text: String, style: String = "Regular", ext: String = "ttf")
        -> FaceRecord
    {
        ShellFaces.make(family, style: style, path: root.appending(path: file + "." + ext).path, text: text)
    }
    func model(_ faces: [FaceRecord], text: String = "ab漢c") -> AppModel {
        let model = AppModel(services: .testing(root: root, defaults: temp.defaults, renderer: renderer))
        model.edit { recipe in
            for face in faces { recipe.add(face) }; recipe.setSampleText(text)
        }
        return model
    }
    func styled(_ mix: Mix, text: String, size: Int = 30, colour: Bool = false) -> (
        AppModel, PreviewTextView, PreviewTextEditor.Coordinator
    ) {
        let model = model([], text: text); model.trial = PreviewTrial(mix: mix, banner: "test")
        model.previewPointSize = size; model.colourByFont = colour
        let editor = PreviewTextEditor.makeEditor(model: model)
        return (model, editor.textView, editor.coordinator)
    }
    static let script = #"""
        from pathlib import Path
        import sys
        from fontTools.fontBuilder import FontBuilder
        from fontTools.pens.ttGlyphPen import TTGlyphPen
        from fontTools.pens.t2CharStringPen import T2CharStringPen
        from fontTools.ttLib.tables.TupleVariation import TupleVariation
        from fontTools.feaLib.builder import addOpenTypeFeaturesFromString

        def build(file, family, chars, style="Regular", upem=1000, cff=False, weight=400, variable=False, latin=False):
            # Port of reference/tests/fixtures.py:31-95, adding SPACE and explicit PostScript names (WP-504 S5).
            cps=sorted({ord(c) for c in chars}|{32})
            names=[".notdef"]+[f"uni{cp:04X}" for cp in cps]
            k=upem/1000; advance=round(200*k); lsb=round(50*k)
            fb=FontBuilder(upem,isTTF=not cff)
            fb.setupGlyphOrder(names);fb.setupCharacterMap({cp:f"uni{cp:04X}" for cp in cps})
            glyphs={}
            for name in names:
                pen=T2CharStringPen(advance,None) if cff else TTGlyphPen(None)
                pen.moveTo((lsb,0));pen.lineTo((round(150*k),0));pen.lineTo((round(150*k),round(700*k)));pen.lineTo((lsb,round(700*k)));pen.closePath()
                glyphs[name]=pen.getCharString() if cff else pen.glyph()
            ps=(family+"-"+style).replace(" ","")
            if cff: fb.setupCFF(ps,{"FullName":family+" "+style},glyphs,{})
            else: fb.setupGlyf(glyphs)
            fb.setupHorizontalMetrics({name:(advance,lsb) for name in names})
            fb.setupHorizontalHeader(ascent=round(800*k),descent=-round(200*k))
            fb.setupNameTable({"familyName":family,"styleName":style,"psName":ps,"fullName":family+" "+style})
            fb.setupOS2(sTypoAscender=round(800*k),sTypoDescender=-round(200*k),usWinAscent=round(800*k),usWinDescent=round(200*k),usWeightClass=weight,fsType=0)
            fb.setupPost()
            if variable:
                fb.setupFvar([("wght",100,400,900,"Weight")],[])
                deltas=[(0,0),(100,0),(100,0),(0,0),(0,0),(100,0),(0,0),(0,0)]
                fb.setupGvar({name:[TupleVariation({"wght":(0.0,1.0,1.0)},deltas)] for name in names})
            if latin: addOpenTypeFeaturesFromString(fb.font,"languagesystem latn dflt;\nfeature liga { sub uni0061 uni0062 by uni0062; } liga;\n")
            fb.save(str(Path(sys.argv[1])/file))

        build("A.ttf","Fixture A","abc1,")
        build("B.otf","Fixture B","ab漢，",style="Bold",weight=700,cff=True)
        build("C.ttf","Fixture C","a→Ω",upem=2048)
        build("V.ttf","Fixture V","ab",variable=True)
        chars="abابدغ"+"".join(chr(cp) for cp in range(0xFE8D,0xFED1))
        build("R.ttf","Fixture Arabic",chars,latin=True)
        build("R0.ttf","Fixture Arabic Plain",chars)
        """#
}
@MainActor func previewFont(_ view: PreviewTextView, at index: Int) -> CTFont {
    view.textStorage!.attribute(.font, at: index, effectiveRange: nil) as! CTFont
}
@MainActor func previewURL(_ font: CTFont) -> URL? { CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL }
