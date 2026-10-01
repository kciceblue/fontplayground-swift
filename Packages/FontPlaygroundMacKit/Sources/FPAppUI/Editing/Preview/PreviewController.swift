import AppKit
import CoreText
import FPCore
import FPMacServices

@MainActor final class PreviewController {
    weak var textView: PreviewTextView?
    private var coverages: [URL: CharacterSet] = [:]
    private var failedURLs = Set<URL>()
    func replaceAllUndoably(with text: String) -> Bool {
        guard let view = textView else { return false }
        guard view.string != text else { return true }
        let range = NSRange(location: 0, length: (view.string as NSString).length)
        view.breakUndoCoalescing()
        if view.shouldChangeText(in: range, replacementString: text) {
            view.textStorage?.replaceCharacters(in: range, with: text); view.didChangeText()
        }
        view.breakUndoCoalescing(); return true
    }
    func focus() { if let view = textView { view.window?.makeFirstResponder(view) } }
    func builtCoverage(for url: URL, renderer: any FontRendering) -> CharacterSet? {
        if let coverage = coverages[url] { return coverage }
        if failedURLs.contains(url) { return nil }
        do {
            let font = try renderer.builtFont(at: url, pointSize: 30);
            let coverage = CTFontCopyCharacterSet(font.ctFont) as CharacterSet; coverages[url] = coverage;
            return coverage
        } catch {
            failedURLs.insert(url);
            AppLog.app.error(
                "Couldn't preview the built font at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            ); return nil
        }
    }
}
extension AppModel {
    var previewConfiguration: PreviewConfiguration {
        let coverage = builtFont.flatMap { previewController.builtCoverage(for: $0.url, renderer: renderer) }
        return .make(
            recipe: recipe, trial: trial, built: builtFont, builtCoverage: coverage, pointSize: previewPointSize,
            colourByFont: colourByFont)
    }
}
