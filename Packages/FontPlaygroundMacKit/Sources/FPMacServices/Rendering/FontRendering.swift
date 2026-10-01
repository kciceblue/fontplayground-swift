import CoreText
import FPCore
import Foundation

public struct FaceRenderRequest: Hashable, Sendable {
    public var face: FaceRecord
    public var pointSize: CGFloat
    public var weight: Int?
    public var scale: Double

    public init(face: FaceRecord, pointSize: CGFloat, weight: Int? = nil, scale: Double = 1) {
        self.face = face
        self.pointSize = pointSize
        self.weight = weight
        self.scale = scale
    }
}

public struct SyntheticBold: Hashable, Sendable {
    public var delta: Int
    public var strokeWidthPercent: Double
    public var extraAdvance: CGFloat
}

public enum RenderWeightNote: Hashable, Sendable {
    case cannotLighten
}

// S7: CTFont is immutable and CoreText permits concurrent reads.
public struct RenderedFont: @unchecked Sendable {
    public let ctFont: CTFont
    public let fileURL: URL
    public let postscriptName: String
    public let pointSize: CGFloat
    public let variation: [String: Double]
    public let syntheticBold: SyntheticBold?
    public let weightNote: RenderWeightNote?

    /// Allows injected renderers to return the same immutable value across module boundaries.
    public init(
        ctFont: CTFont, fileURL: URL, postscriptName: String, pointSize: CGFloat,
        variation: [String: Double] = [:], syntheticBold: SyntheticBold? = nil,
        weightNote: RenderWeightNote? = nil
    ) {
        self.ctFont = ctFont; self.fileURL = fileURL; self.postscriptName = postscriptName
        self.pointSize = pointSize; self.variation = variation; self.syntheticBold = syntheticBold
        self.weightNote = weightNote
    }
}

public enum RenderError: Error, Hashable, LocalizedError {
    case fileMissing(path: String)
    case unreadable(path: String)
    case faceNotFound(path: String, index: Int, postscriptName: String?)
    case builtFontInvalid(path: String, faceCount: Int)

    public var englishText: String {
        switch self {
        case .fileMissing: "The font file is missing."
        case .unreadable: "macOS can't read this font file."
        case .faceNotFound: "This font is no longer in its file."
        case .builtFontInvalid: "The built font file is not a single font."
        }
    }

    public var errorDescription: String? { englishText }
}

public protocol FontRendering: Sendable {
    func font(for request: FaceRenderRequest) throws -> RenderedFont
    func builtFont(at url: URL, pointSize: CGFloat) throws -> RenderedFont
    func hasGlyph(for scalar: Unicode.Scalar, in font: RenderedFont) -> Bool
    func missingScalars(in text: String, for font: RenderedFont) -> [Unicode.Scalar]
    func coverage(of font: RenderedFont) -> CodepointSet
    func invalidate(path: String)
    func invalidateAll()
}
