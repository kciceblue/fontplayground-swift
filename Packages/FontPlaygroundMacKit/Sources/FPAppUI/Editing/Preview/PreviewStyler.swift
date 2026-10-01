import AppKit
import CoreText
import FPCore
import FPMacServices
import os

@MainActor final class PreviewStyler: NSObject, NSTextStorageDelegate {
    private weak var textView: PreviewTextView?
    private let renderer: any FontRendering
    private(set) var configuration: PreviewConfiguration
    private let recordsHistory: Bool
    private var isRestyling = false
    private var sources: [UInt32: Int] = [:]
    private var attributes: [[NSAttributedString.Key: Any]] = []
    private var missing: [NSAttributedString.Key: Any] = [:]
    private var failedPaths = Set<String>()
    private(set) var restyledRanges: [NSRange] = []
    private let signposter = OSSignposter(subsystem: AppLog.subsystem, category: "Preview")
    init(
        textView: PreviewTextView, renderer: any FontRendering, configuration: PreviewConfiguration,
        recordsHistory: Bool = false
    ) {
        self.textView = textView; self.renderer = renderer; self.configuration = configuration;
        self.recordsHistory = recordsHistory
        super.init(); rebuildFonts(); textView.textStorage?.delegate = self; restyleAll()
    }
    func resetRestyleLog() { restyledRanges = [] }
    func apply(_ configuration: PreviewConfiguration) {
        guard self.configuration != configuration else { return }
        let interval = signposter.beginInterval("PreviewModeChange");
        defer { signposter.endInterval("PreviewModeChange", interval) }
        self.configuration = configuration; sources = [:]; rebuildFonts(); restyleAll()
    }
    nonisolated func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        MainActor.assumeIsolated {
            guard let textStorage = self.textView?.textStorage, !isRestyling,
                editedMask.contains(.editedCharacters) || editedMask.contains(.editedAttributes)
            else {
                return
            }
            let interval = signposter.beginInterval("PreviewRestyle");
            defer { signposter.endInterval("PreviewRestyle", interval) }
            let range = (textStorage.string as NSString).paragraphRange(
                for: NSIntersectionRange(editedRange, NSRange(location: 0, length: textStorage.length)))
            restyle(range)
        }
    }
    private func source(_ scalar: Unicode.Scalar) -> Int? {
        if let cached = sources[scalar.value] { return cached < 0 ? nil : cached }
        let value = configuration.source(of: scalar); sources[scalar.value] = value ?? -1; return value
    }
    private func rebuildFonts() {
        let size = CGFloat(configuration.pointSize)
        let fonts: [CTFont]
        let baseIndex: Int
        if let mix = configuration.mix, !mix.fonts.isEmpty {
            var cache: [FaceRenderRequest: CTFont] = [:]
            fonts = mix.fonts.map { font in
                let request = FaceRenderRequest(face: font.face, pointSize: size * font.scale, weight: font.weight)
                if let cached = cache[request] { return cached }
                let rendered: CTFont
                do { rendered = try renderer.font(for: request).ctFont } catch {
                    rendered = missingFont(size: size * font.scale, path: font.face.path, error: error)
                }
                cache[request] = rendered; return rendered
            }
            baseIndex = min(max(0, mix.baseIndex), fonts.count - 1)
        } else if case .built(let built, _) = configuration.mode {
            do { fonts = [try renderer.builtFont(at: built.url, pointSize: size).ctFont] } catch {
                fonts = [missingFont(size: size, path: built.url.path, error: error)]
            }
            baseIndex = 0
        } else {
            fonts = [NSFont.systemFont(ofSize: size) as CTFont]; baseIndex = 0
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.baseWritingDirection = .natural;
        paragraph.alignment = .natural
        if configuration.mode != .empty {
            let font = fonts[baseIndex],
                height = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
            paragraph.minimumLineHeight = height; paragraph.maximumLineHeight = height
        }
        attributes = fonts.enumerated().map { index, font in
            let colour: NSColor
            if configuration.mode == .empty {
                colour = .tertiaryLabelColor
            } else if configuration.mix != nil && configuration.colourByFont {
                colour = MixPalette.colour(forMaterialAt: index)
            } else {
                colour = .textColor
            }
            var result: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: colour, .paragraphStyle: paragraph,
            ]
            if let mix = configuration.mix, mix.fonts.indices.contains(index) {
                let material = mix.fonts[index],
                    delta = (material.weight ?? material.face.weightClass) - material.face.weightClass
                if !material.face.axes.contains(where: { $0.tag == "wght" }), delta >= 50 {
                    let d = Double(min(delta, 500))
                    result[.strokeWidth] = -(d * 0.02); result[.strokeColor] = colour
                    result[.kern] = d / 1000 * 0.2 * CTFontGetSize(font)
                }
            }
            return result
        }
        missing = [
            .font: fonts[0], .foregroundColor: NSColor.textColor, .backgroundColor: MixPalette.missingBackground,
            .paragraphStyle: paragraph,
        ]
        textView?.typingAttributes = attributes[0]
    }
    private func missingFont(size: CGFloat, path: String, error: any Error) -> CTFont {
        if failedPaths.insert(path).inserted {
            AppLog.app.error(
                "Couldn't preview font at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        // A vanished material stays a LastResort box; borrowing a different font would misrepresent the result.
        return CTFontCreateWithFontDescriptor(LastResort.shared.descriptor, size, nil)
    }
    private func restyleAll() {
        guard let view = textView, let storage = view.textStorage else { return }
        restyle(NSRange(location: 0, length: storage.length)); view.typingAttributes = attributes[0]
    }
    private func restyle(_ range: NSRange) {
        guard let view = textView, let storage = view.textStorage, !isRestyling else { return }
        isRestyling = true; defer { isRestyling = false }
        if recordsHistory { restyledRanges.append(range) }
        let undo = view.undoManager, registration = undo?.isUndoRegistrationEnabled == true
        if registration { undo?.disableUndoRegistration() }
        defer { if registration { undo?.enableUndoRegistration() } }
        storage.beginEditing()
        let string = storage.string as NSString
        var start = range.location
        while start < NSMaxRange(range) {
            let paragraphRange = string.paragraphRange(for: NSRange(location: start, length: 0))
            let text = string.substring(with: paragraphRange)
            for run in PreviewRuns.runs(text[...], source: source) {
                let attrs = run.source.flatMap { attributes.indices.contains($0) ? attributes[$0] : nil } ?? missing
                storage.setAttributes(
                    attrs, range: NSRange(location: start + run.range.location, length: run.range.length))
            }
            start = NSMaxRange(paragraphRange)
        }
        storage.endEditing(); view.typingAttributes = attributes[0]
    }
}
