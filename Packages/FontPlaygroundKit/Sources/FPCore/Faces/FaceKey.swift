import Foundation

public struct FaceKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var path: String
    public var index: Int

    public init(path: String, index: Int) {
        self.path = path
        self.index = index
    }

    public static func < (lhs: FaceKey, rhs: FaceKey) -> Bool {
        lhs.path == rhs.path ? lhs.index < rhs.index : lhs.path < rhs.path
    }

    public var description: String { "\(path)#\(index)" }
}
