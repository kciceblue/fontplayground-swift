import FPCore
import Foundation

@testable import FPAppUI

@MainActor enum ShellFaces {
    static func make(
        _ family: String = "Fixture A", style: String = "Regular", path: String = "/fixture/A.ttf",
        postscriptName: String? = nil, text: String = "abc你好", index: Int = 0
    ) -> FaceRecord {
        let coverage = CodepointSet(scalarsOf: text)
        var counts: [String: Int] = [:]
        for scalar in text.unicodeScalars { counts[ScriptGroup.of(scalar.value).rawValue, default: 0] += 1 }
        let object: [String: Any] = [
            "path": path, "index": index, "family": family, "style": style,
            "postscript_name": postscriptName ?? (family.replacingOccurrences(of: " ", with: "") + "-" + style),
            "coverage": coverage.ranges.map { [$0.lowerBound, $0.upperBound] }, "group_counts": counts,
            "weight_class": 400, "upem": 1000, "glyph_count": coverage.count + 1, "outline": "glyf", "size": 1,
            "mtime": 1.0,
        ]
        return try! JSONDecoder().decode(FaceRecord.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
