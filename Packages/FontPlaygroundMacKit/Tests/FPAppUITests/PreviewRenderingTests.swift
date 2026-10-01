import AppKit
import CoreText
import FPCore
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor @Suite struct PreviewRenderingTests {
    @Test func eachCharacterIsDrawnInTheFontThatDrawsIt() throws {
        let f = try PreviewFixtureFonts(), m = f.model([f.a, f.b]), e = PreviewTextEditor.makeEditor(model: m),
            v = e.textView
        #expect((0..<4).map { previewURL(previewFont(v, at: $0))?.path } == [f.a.path, f.a.path, f.b.path, f.a.path])
        #expect(PreviewRuns.sources("ab漢c"[...].unicodeScalars, source: m.previewConfiguration.source) == [0, 0, 1, 0])
        let runs = RunInspector.runs(of: v.textStorage!)
        #expect(
            runs.map(\.range) == [
                NSRange(location: 0, length: 2), NSRange(location: 2, length: 1), NSRange(location: 3, length: 1),
            ])
        #expect(previewURL(v.typingAttributes[.font] as! CTFont)?.path == f.a.path)
        #expect(m.previewConfiguration.missingScalars(in: v.string).isEmpty && v.textLayoutManager != nil)
    }
    @Test func sizeAndScaleReachTheRuns() throws {
        let f = try PreviewFixtureFonts(), m = f.model([f.a, f.b]);
        m.edit { $0.setAdjustments(for: f.b.key, weight: nil, scale: 0.8) }
        let e = PreviewTextEditor.makeEditor(model: m), v = e.textView
        #expect(CTFontGetSize(previewFont(v, at: 0)) == 30 && CTFontGetSize(previewFont(v, at: 2)) == 24)
        m.previewPointSize = 20; e.coordinator.refresh()
        #expect(CTFontGetSize(previewFont(v, at: 0)) == 20 && CTFontGetSize(previewFont(v, at: 2)) == 16)
        #expect(CTFontGetSize(v.typingAttributes[.font] as! CTFont) == 20)
        m.trial = PreviewTrial(mix: Mix(fonts: [.init(face: f.a), .init(face: f.b, scale: 0.5)]), banner: "test")
        m.previewPointSize = 30; m.recipe.setSampleText(" 漢 a"); e.coordinator.refresh()
        #expect(CTFontGetSize(previewFont(v, at: 0)) == 15 && CTFontGetSize(previewFont(v, at: 2)) == 15)
    }
    @Test func variableWeightAndSyntheticBoldApproximation() throws {
        let f = try PreviewFixtureFonts()
        let (m, v, c) = f.styled(Mix(fonts: [.init(face: f.v, weight: 700)]), text: "ab")
        let variations = CTFontCopyVariation(previewFont(v, at: 0)) as? [NSNumber: NSNumber]
        #expect(variations?[NSNumber(value: 0x77676874)]?.doubleValue == 700)
        for (weight, stroke, kern) in [(700, -6.0, 1.8), (430, 0.0, 0.0), (1000, -10.0, 3.0), (300, 0.0, 0.0)] {
            m.trial = PreviewTrial(mix: Mix(fonts: [.init(face: f.a, weight: weight)]), banner: ""); c.refresh()
            let attrs = v.textStorage!.attributes(at: 0, effectiveRange: nil)
            #expect((attrs[.strokeWidth] as? Double ?? 0) == stroke)
            #expect(abs((attrs[.kern] as? Double ?? 0) - kern) < 0.0001)
            if stroke == 0 { #expect(attrs[.strokeWidth] == nil && attrs[.kern] == nil) }
        }
    }
    @Test func missingIsMarkedButSpacesAndJoinersNeverAre() throws {
        let f = try PreviewFixtureFonts(), m = f.model([f.a], text: "a 漢‍b"), e = PreviewTextEditor.makeEditor(model: m),
            v = e.textView
        #expect(
            v.textStorage!.attribute(.backgroundColor, at: 2, effectiveRange: nil) as? NSColor
                == MixPalette.missingBackground)
        #expect(previewURL(previewFont(v, at: 2))?.path == f.a.path)
        #expect(
            [0, 1, 3, 4].allSatisfy { v.textStorage!.attribute(.backgroundColor, at: $0, effectiveRange: nil) == nil })
        #expect(m.previewConfiguration.missingScalars(in: v.string).map(String.init) == ["漢"])
        m.recipe.setSampleText(" 漢 "); e.coordinator.refresh()
        #expect(
            v.textStorage!.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil
                && v.textStorage!.attribute(.backgroundColor, at: 2, effectiveRange: nil) == nil)
    }
    @Test func colourByFont() throws {
        let f = try PreviewFixtureFonts(), m = f.model([f.a, f.b], text: "a漢한"); m.colourByFont = true
        let e = PreviewTextEditor.makeEditor(model: m), v = e.textView
        #expect(
            v.textStorage!.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                == MixPalette.colour(forMaterialAt: 0))
        #expect(
            v.textStorage!.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
                == MixPalette.colour(forMaterialAt: 1))
        #expect(v.textStorage!.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor == .textColor)
        #expect(v.textStorage!.attribute(.backgroundColor, at: 2, effectiveRange: nil) != nil)
        m.colourByFont = false; e.coordinator.refresh()
        #expect(
            (0..<3).allSatisfy {
                v.textStorage!.attribute(.foregroundColor, at: $0, effectiveRange: nil) as? NSColor == .textColor
            })
        m.colourByFont = true;
        m.builtFont = .init(url: URL(fileURLWithPath: f.a.path), displayName: "built", spec: m.recipe.forgeSpec());
        e.coordinator.refresh()
        #expect(
            (0..<3).allSatisfy {
                v.textStorage!.attribute(.foregroundColor, at: $0, effectiveRange: nil) as? NSColor == .textColor
            })
    }
    @Test("CATALOG-4: built font draws its file, not a registered namesake")
    func builtFontDrawsTheFileNotASameNamedRegisteredFont() throws {
        let f = try PreviewFixtureFonts(), url = URL(fileURLWithPath: f.a.path),
            copy = f.root.appending(path: "same-name.ttf")
        try FileManager.default.copyItem(at: url, to: copy)
        #expect(CTFontManagerRegisterFontsForURL(copy as CFURL, .process, nil));
        defer { CTFontManagerUnregisterFontsForURL(copy as CFURL, .process, nil) }
        let m = f.model([f.a], text: "abc");
        m.builtFont = .init(url: url, displayName: f.a.displayName, spec: m.recipe.forgeSpec())
        let e = PreviewTextEditor.makeEditor(model: m)
        #expect(RunInspector.runs(of: e.textView.textStorage!).allSatisfy { $0.fileURL?.path == url.path })
    }
    @Test("NATIVE-M1: runs use CoreText without fallback") func nativeM1RunsAreCoreTextWithoutFallback() throws {
        let f = try PreviewFixtureFonts(), m = f.model([f.a], text: "ab 漢 →"),
            e = PreviewTextEditor.makeEditor(model: m)
        let first = RunInspector.runs(of: e.textView.textStorage!)
        #expect(
            first.map(\.range) == [
                NSRange(location: 0, length: 3), NSRange(location: 3, length: 1), NSRange(location: 4, length: 1),
                NSRange(location: 5, length: 1),
            ])
        #expect(
            first.enumerated().allSatisfy {
                $0.offset % 2 == 0
                    ? $0.element.fileURL?.path == f.a.path : $0.element.fileURL?.lastPathComponent == "LastResort.otf"
            })
        m.edit { $0.add(f.b) }; e.coordinator.refresh()
        let second = RunInspector.runs(of: e.textView.textStorage!)
        #expect(
            second.allSatisfy {
                [f.a.path, f.b.path, "/System/Library/Fonts/LastResort.otf"].contains($0.fileURL?.path ?? "")
            })
        #expect(
            second.filter { $0.fileURL?.lastPathComponent == "LastResort.otf" }.map(\.range) == [
                NSRange(location: 5, length: 1)
            ])
    }
    @Test("NATIVE-M1: built font matches CoreText Arabic shaping") func nativeM1BuiltFontMatchesCoreTextShaping() throws
    {
        let f = try PreviewFixtureFonts(), text = "بغداد"
        for face in [f.r, f.r0] {
            let m = f.model([face], text: text), url = URL(fileURLWithPath: face.path)
            m.builtFont = .init(url: url, displayName: face.displayName, spec: m.recipe.forgeSpec())
            let e = PreviewTextEditor.makeEditor(model: m)
            let descriptor = try #require(
                (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first)
            let font = CTFontCreateWithFontDescriptor(descriptor, 30, nil),
                reference = NSAttributedString(string: text, attributes: [.font: font])
            let actual = RunInspector.runs(of: e.textView.textStorage!).flatMap(\.glyphs),
                expected = RunInspector.runs(of: reference).flatMap(\.glyphs)
            #expect(actual == expected)
            var chars = Array(text.utf16), nominal = [CGGlyph](repeating: 0, count: chars.count)
            CTFontGetGlyphsForCharacters(font, &chars, &nominal, chars.count)
            var presentationChars = (0xFE8D...0xFED0).map(UInt16.init),
                presentation = [CGGlyph](repeating: 0, count: presentationChars.count)
            CTFontGetGlyphsForCharacters(font, &presentationChars, &presentation, presentationChars.count)
            if face.path == f.r.path {
                #expect(actual == Array(nominal.reversed()) && Set(actual).isDisjoint(with: presentation))
            } else {
                #expect(!Set(actual).isDisjoint(with: presentation))
            }
        }
    }
    @Test func rtlParagraphsUseNaturalDirection() throws {
        let f = try PreviewFixtureFonts(), m = f.model([f.r0], text: "abc\nمرحبا"),
            e = PreviewTextEditor.makeEditor(model: m)
        let paragraph = try #require(
            e.textView.textStorage!.attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.baseWritingDirection == .natural && paragraph.alignment == .natural)
        let line = CTLineCreateWithAttributedString(
            e.textView.textStorage!.attributedSubstring(from: NSRange(location: 4, length: 5)))
        #expect((CTLineGetGlyphRuns(line) as! [CTRun]).allSatisfy { CTRunGetStatus($0).contains(.rightToLeft) })
    }
    @Test func lineHeightComesFromTheBaseFont() throws {
        let f = try PreviewFixtureFonts(), mix = Mix(fonts: [.init(face: f.a), .init(face: f.b, scale: 0.8)])
        let (m, v, c) = f.styled(mix, text: "a漢")
        for base in [0, 1] {
            m.trial = PreviewTrial(mix: Mix(fonts: mix.fonts, baseIndex: base), banner: ""); c.refresh()
            let font = previewFont(v, at: base),
                expected = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
            let layout = try #require(v.textLayoutManager),
                range = try #require(layout.textContentManager?.documentRange)
            layout.ensureLayout(for: range)
            var heights: [CGFloat] = []
            layout.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) { fragment in
                heights += fragment.textLineFragments.map(\.typographicBounds.height); return true
            }
            #expect(!heights.isEmpty && heights.allSatisfy { abs($0 - expected) <= 0.5 })
        }
    }
    @Test func emptyRecipeDrawsAFaintPlaceholderFont() throws {
        let f = try PreviewFixtureFonts(), m = f.model([], text: "abc 漢\n𠀀"),
            e = PreviewTextEditor.makeEditor(model: m), v = e.textView
        #expect(m.previewConfiguration.missingScalars(in: v.string).isEmpty)
        for index in 0..<v.textStorage!.length {
            #expect(
                v.textStorage!.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
                    == .tertiaryLabelColor)
            #expect(v.textStorage!.attribute(.backgroundColor, at: index, effectiveRange: nil) == nil)
            #expect(CTFontGetSize(previewFont(v, at: index)) == 30)
        }
        m.previewPointSize = 12; e.coordinator.refresh();
        #expect(CTFontGetSize(previewFont(v, at: 0)) == 12 && v.textLayoutManager != nil)
    }
}
