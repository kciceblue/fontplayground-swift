import AppKit
import CoreText
import FPCore

@MainActor final class FontRowCellView: NSTableCellView {
    private var row: PickerRow?
    private var language = Languages.language(.any)
    private weak var cache: RowFontCache?
    private(set) var drewInOwnFace = false
    override var isFlipped: Bool { true }
    override var backgroundStyle: NSView.BackgroundStyle { didSet { needsDisplay = true } }

    func configure(row: PickerRow, language: Language, cache: RowFontCache) {
        self.row = row; self.language = language; self.cache = cache
        setAccessibilityElement(true)
        switch row {
        case .header(let header):
            if #available(macOS 26.0, *) {
                setAccessibilityRole(.headingRole)
            } else {
                setAccessibilityRole(.staticText)
            }
            setAccessibilityLabel(header.accessibilityLabel); setAccessibilityHelp(nil)
        case .family(let family):
            setAccessibilityRole(.cell)
            setAccessibilityLabel(
                PickerText.rowAccessibilityLabel(
                    family: family.family, nativeName: family.nativeName, inRecipe: family.inRecipe,
                    unavailableReason: family.unavailableReason))
            setAccessibilityHelp(PickerText.sampleHelp(language.pickerSample))
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drewInOwnFace = false
        guard let row, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        switch row {
        case .header(let header):
            draw(
                header.title, font: systemFont(13), x: 8, baseline: 6, width: bounds.width - 16,
                colour: .secondaryLabelColor, context: context)
        case .family(let family):
            let selected = backgroundStyle == .emphasized
            let foreground: NSColor =
                family.unavailableReason != nil
                ? .tertiaryLabelColor : selected ? .alternateSelectedControlTextColor : .labelColor
            let secondary: NSColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
            let tag = family.unavailableReason ?? (family.inRecipe ? PickerText.inYourFont : "")
            let tagWidth = min(bounds.width * 0.6, width(tag, font: systemFont(11)))
            let available = max(0, bounds.width - 16 - (tag.isEmpty ? 0 : tagWidth + 10))
            let nativeWidth =
                family.nativeName.isEmpty ? 0 : min(available * 0.4, width(family.nativeName, font: systemFont(11)))
            let nameWidth = max(0, available - (nativeWidth == 0 ? 0 : nativeWidth + 8))
            let nameFont = labelFont(family.family, face: family.face, size: 14)
            draw(
                family.family, font: nameFont, x: 8, baseline: bounds.height - 20, width: nameWidth, colour: foreground,
                context: context)
            if nativeWidth > 0 {
                let x = 8 + min(nameWidth, width(family.family, font: nameFont)) + 8
                draw(
                    family.nativeName, font: labelFont(family.nativeName, face: family.face, size: 11), x: x,
                    baseline: bounds.height - 20, width: available - (x - 8), colour: secondary, context: context)
            }
            if !tag.isEmpty {
                draw(
                    tag, font: systemFont(11), x: bounds.width - 8 - tagWidth, baseline: bounds.height - 20,
                    width: tagWidth,
                    colour: family.unavailableReason != nil ? secondary : selected ? foreground : .systemGreen,
                    context: context)
            }
            let own = cache?.font(for: family.face, size: 18)
            drewInOwnFace = own != nil
            draw(
                language.pickerSample, font: own ?? systemFont(18), x: 8, baseline: bounds.height - 49,
                width: bounds.width - 16, colour: own == nil ? secondary : foreground, context: context)
        }
    }
    private func systemFont(_ size: CGFloat) -> CTFont { CTFontCreateUIFontForLanguage(.system, size, nil)! }
    private func labelFont(_ text: String, face: FaceRecord, size: CGFloat) -> CTFont {
        if TextUtil.visibleScalars(in: text).allSatisfy({ face.coverage.contains($0) }),
            let font = cache?.font(for: face, size: size)
        {
            return font
        }
        return systemFont(size)
    }
    private func line(_ text: String, font: CTFont) -> CTLine {
        CTLineCreateWithAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
                ]))
    }
    private func width(_ text: String, font: CTFont) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, font: font), nil, nil, nil))
    }
    private func draw(
        _ text: String, font: CTFont, x: CGFloat, baseline: CGFloat, width: CGFloat, colour: NSColor, context: CGContext
    ) {
        guard width > 0, !text.isEmpty else { return }
        let source = line(text, font: font)
        let drawn = CTLineCreateTruncatedLine(source, Double(width), .end, line("…", font: font)) ?? source
        context.setFillColor(colour.cgColor); context.textPosition = CGPoint(x: x, y: baseline);
        CTLineDraw(drawn, context)
    }
}
