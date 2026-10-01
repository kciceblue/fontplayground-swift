import Foundation

public struct ForgeRequest: Codable, Sendable, Equatable {
    public var spec: ForgeSpec
    public var outputPath: String

    public init(spec: ForgeSpec, outputPath: String) {
        self.spec = spec
        self.outputPath = outputPath
    }

    private enum CodingKeys: String, CodingKey {
        case spec
        case outputPath = "output_path"
    }

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
