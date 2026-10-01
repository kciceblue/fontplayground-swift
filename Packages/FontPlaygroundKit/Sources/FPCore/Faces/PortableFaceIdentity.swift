import Foundation

public struct PortableFaceIdentity: Codable, Sendable, Hashable {
    public var postscriptName: String?
    public var family: String
    public var style: String
    public var path: String
    public var index: Int
    public var key: FaceKey { FaceKey(path: path, index: index) }
    public var displayName: String { "\(family) \(style)" }

    public init(postscriptName: String?, family: String, style: String, path: String, index: Int) {
        self.postscriptName = postscriptName
        self.family = family
        self.style = style
        self.path = path
        self.index = index
    }

    private enum CodingKeys: String, CodingKey {
        case postscriptName = "postscript_name"
        case family, style, path, index
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(postscriptName, forKey: .postscriptName)
        try values.encode(family, forKey: .family)
        try values.encode(style, forKey: .style)
        try values.encode(path, forKey: .path)
        try values.encode(index, forKey: .index)
    }
}
