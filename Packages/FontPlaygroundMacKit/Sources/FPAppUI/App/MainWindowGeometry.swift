import Foundation

public enum MainWindowGeometry {
    public static let minContentSize = CGSize(width: 640, height: 480)
    public static let preferredFrameSize = CGSize(width: 1280, height: 848)
    // Initial sidebar (280), preview minimum (360), and inspector ideal (300).
    public static let minWidthWithSidebarAndInspector = 940.0
    // Preview minimum (360) and inspector ideal (300).
    public static let minWidthWithInspector = 660.0
    public static func initialFrame(visibleFrame v: CGRect, chromeHeight: CGFloat) -> CGRect {
        let w = max(minContentSize.width, min(preferredFrameSize.width, floor(0.9 * v.width)))
        let h = max(minContentSize.height + chromeHeight, min(preferredFrameSize.height, floor(0.9 * v.height)))
        let x = w > v.width ? v.minX : v.minX + floor((v.width - w) / 2)
        let y = h > v.height ? v.maxY - h : v.minY + floor((v.height - h) / 2)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
