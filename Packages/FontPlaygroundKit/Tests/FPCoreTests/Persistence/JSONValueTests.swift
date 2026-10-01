import FPCore
import Foundation
import Testing

struct JSONValueTests {
    @Test func distinguishesBoolsFromNumbers() throws {
        let data = Data(#"[true,false,1,0,1.5,"1",null,{},[]]"#.utf8)
        #expect(
            try JSONDecoder().decode([JSONValue].self, from: data) == [
                .bool(true), .bool(false), .integer(1), .integer(0), .number(1.5), .string("1"), .null, .object([:]),
                .array([]),
            ])
        let decimal = try JSONDecoder().decode(JSONValue.self, from: Data("700.0".utf8))
        #expect(decimal == .integer(700) || decimal == .number(700))
        #expect(decimal.asInt == 700 || decimal.asInt == nil)
        #expect(JSONValue.bool(true).asInt == nil)
        #expect(JSONValue.string("nan").asFloat == nil && JSONValue.string("inf").asFloat == nil)
        #expect(JSONValue.string(" 1.5").asFloat == 1.5 && JSONValue.string(" 7 ").asInt == 7)
        #expect(JSONValue.array([.string("/a"), .string("0")]).asKey == FaceKey(path: "/a", index: 0))
    }
}
