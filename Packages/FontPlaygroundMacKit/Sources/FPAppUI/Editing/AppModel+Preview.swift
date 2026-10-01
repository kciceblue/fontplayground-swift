import FPCore

extension AppModel {
    public func zoomPreviewIn() { previewPointSize = PreviewZoom.next(after: previewPointSize) }
    public func zoomPreviewOut() { previewPointSize = PreviewZoom.previous(before: previewPointSize) }
    public func resetPreviewZoom() { previewPointSize = PreviewZoom.defaultSize }
    public func applySample(id: String) {
        guard let sample = Samples.presets.first(where: { $0.id == id }) else { return }
        if !previewController.replaceAllUndoably(with: sample.text) { recipe.setSampleText(sample.text) }
    }
    public func focusPreview() { previewController.focus() }
}
