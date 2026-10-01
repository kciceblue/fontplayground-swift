import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case null, bool(Bool), integer(Int), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        if values.decodeNil() {
            self = .null
        } else if let value = try? values.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? values.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? values.decode(Double.self) {
            self = .number(value)
        } else if let value = try? values.decode(String.self) {
            self = .string(value)
        } else if let value = try? values.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try values.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.singleValueContainer()
        switch self {
        case .null: try values.encodeNil()
        case .bool(let value): try values.encode(value)
        case .integer(let value): try values.encode(value)
        case .number(let value): try values.encode(value)
        case .string(let value): try values.encode(value)
        case .array(let value): try values.encode(value)
        case .object(let value): try values.encode(value)
        }
    }

    public var asInt: Int? {
        switch self {
        case .integer(let value): value;
        case .string(let value): Int(Naming.cleanName(value));
        default: nil
        }
    }
    public var asFloat: Double? {
        let value: Double?
        switch self {
        case .integer(let number): value = Double(number)
        case .number(let number): value = number
        case .string(let string): value = Double(Naming.cleanName(string))
        default: value = nil
        }
        return value.flatMap { $0.isFinite ? $0 : nil }
    }
    public var asKey: FaceKey? {
        guard case .array(let values) = self, values.count == 2,
            case .string(let path) = values[0], let index = values[1].asInt
        else { return nil }
        return FaceKey(path: path, index: index)
    }
    var string: String? { if case .string(let value) = self { value } else { nil } }
    var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    var truthy: Bool {
        switch self {
        case .null: false
        case .bool(let value): value
        case .integer(let value): value != 0
        case .number(let value): value != 0
        case .string(let value): !value.isEmpty
        case .array(let value): !value.isEmpty
        case .object(let value): !value.isEmpty
        }
    }
    var description: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return String(value)
        case .integer(let value): return String(value)
        case .number(let value): return String(value)
        case .string(let value): return value
        case .array, .object:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? ""
        }
    }
}
