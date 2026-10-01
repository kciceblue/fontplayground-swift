import Foundation
import Testing

@testable import FPCore

struct FaceRecordCodingTests {
    private let minimal =
        #"{"path":"/fixtures/a.ttf","index":2,"family":"Fixture A","style":"Regular","coverage":[[97,99]]}"#
    private let complete = #"""
        {"path":"/fixtures/a.ttc","index":3,"size":12345,"mtime":1700.125,"family":"Fixture",
         "style":"Bold","full_name":"Fixture Bold Full","postscript_name":"Fixture-Bold",
         "local_names":["字体"],"outline":"CFF","is_collection":true,"is_variable":true,
         "axes":[{"tag":"wght","min":100,"default":400,"max":900}],"weight_class":700,
         "italic":true,"upem":2048,"glyph_count":99,"coverage":[[97,99],[1575,1576]],
         "unshaped":[[1575,1576]],"group_counts":{"latin":3},"embedding":"preview-print","fs_type":4,
         "has_color":true,"supported":false,"unsupported_reason":"colour fonts are not supported",
         "hidden":true,"suspicious_coverage":true,"ot_scripts":{"gsub":["latn"],"gpos":["hebr"]},
         "aat":{"morx":true,"kerx":true,"kern_v1":true,"trak":true},"shapes_groups":["hebrew"],
         "licence":{"class":"apple-sla","vendor_id":"APPL","notice":"Example notice"},
         "has_os2":false,"is_forged":true,"font_revision":"123.456"}
        """#

    private func decode(_ json: String) throws -> FaceRecord {
        try JSONDecoder().decode(FaceRecord.self, from: Data(json.utf8))
    }

    @Test func decodesEveryContractField() throws {
        let face = try decode(complete)
        #expect(face.path == "/fixtures/a.ttc" && face.index == 3 && face.size == 12345 && face.mtime == 1700.125)
        #expect(face.family == "Fixture" && face.style == "Bold" && face.fullName == "Fixture Bold Full")
        #expect(face.postscriptName == "Fixture-Bold" && face.localNames == ["字体"] && face.outline == .cff)
        #expect(face.isCollection && face.isVariable && face.hasWeightAxis)
        #expect(face.axes == [.init(tag: "wght", min: 100, default: 400, max: 900)])
        #expect(face.weightClass == 700 && face.italic && face.upem == 2048 && face.glyphCount == 99)
        #expect(face.coverage.ranges == [97...99, 1575...1576] && face.unshaped.ranges == [1575...1576])
        #expect(face.plannableCoverage.ranges == [97...99] && face.groupCounts == [.latin: 3])
        #expect(face.embedding == .previewPrint && face.fsType == 4 && face.hasColor && !face.supported)
        #expect(face.unsupportedReason == "colour fonts are not supported" && face.hidden && face.suspiciousCoverage)
        #expect(face.otScripts.gsub == ["latn"] && face.otScripts.gpos == ["hebr"])
        #expect(face.aat == .init(morx: true, kerx: true, kernV1: true, trak: true))
        #expect(face.shapesGroups == [.hebrew])
        #expect(face.licence == .init(licenceClass: .appleSLA, vendorID: "APPL", notice: "Example notice"))
        #expect(!face.hasOS2 && face.isForged && face.fontRevision == "123.456")
        #expect(face.identity.key == face.key && face.displayName == "Fixture Bold")
    }

    @Test func decodesMinimalRecordWithDefaults() throws {
        let face = try decode(minimal)
        #expect(face.size == 0 && face.mtime == 0 && face.fullName == "Fixture A Regular")
        #expect(face.postscriptName == nil && face.fsType == nil && face.localNames.isEmpty && face.axes.isEmpty)
        #expect(face.outline == .glyf && !face.isCollection && !face.isVariable)
        #expect(face.weightClass == 400 && face.upem == 1000 && face.glyphCount == 4 && !face.italic)
        #expect(face.unshaped.isEmpty && face.plannableCoverage == face.coverage && face.groupCounts == [.latin: 3])
        #expect(face.embedding == .installable && face.supported && face.unsupportedReason == nil)
        #expect(!face.hasColor && !face.hidden && !face.suspiciousCoverage && !face.isForged)
        #expect(face.otScripts == .init() && face.aat == .init() && face.licence == .init())
        #expect(face.shapesGroups == nil && face.hasOS2 && face.fontRevision == "")
        #expect(face.canShape(.arabic))
    }

    @Test func ignoresUnknownKeys() throws {
        let extended =
            minimal.dropLast()
            + #", "future_field":{"x":1},"group_counts":{"latin":3,"han":0,"future":5},"shapes_groups":["arabic","future"],"licence":{"class":"new-licence"},"aat":{},"ot_scripts":{}}"#
        let face = try decode(String(extended))
        #expect(face.groupCounts == [.latin: 3] && face.shapesGroups == [.arabic])
        #expect(face.licence.licenceClass == .unknown && face.aat == .init() && face.otScripts == .init())
    }

    @Test func roundTripsThroughJSON() throws {
        for json in [minimal, complete] {
            let original = try decode(json)
            let data = try JSONEncoder().encode(original)
            #expect(try JSONDecoder().decode(FaceRecord.self, from: data) == original)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let reference = try #require(JSONSerialization.jsonObject(with: Data(complete.utf8)) as? [String: Any])
            #expect(Set(object.keys) == Set(reference.keys))
            #expect(object["plannableCoverage"] == nil)
            if original.postscriptName == nil { #expect(object["postscript_name"] is NSNull) }
            if original.shapesGroups == nil { #expect(object["shapes_groups"] is NSNull) }
        }
    }

    @Test func derivesSupportLikeTheScanner() throws {
        for (outline, color, reason): (FaceRecord.Outline, Bool, String) in [
            (.none, true, "bitmap-only font (no outlines)"),
            (.cff2, true, "CFF2 outlines are not supported"),
            (.glyf, true, "colour fonts are not supported"),
        ] {
            let face = FaceRecord(path: "/a", family: "A", coverage: .empty, outline: outline, hasColor: color)
            #expect(!face.supported && face.unsupportedReason == reason)
            let extra = minimal.dropLast() + ",\"outline\":\"\(outline.rawValue)\",\"has_color\":\(color)}"
            #expect(try decode(String(extra)).unsupportedReason == reason)
        }
        do {
            _ = try decode(#"{"index":0,"family":"A","style":"Regular","coverage":[]}"#)
            Issue.record("Missing path decoded")
        } catch DecodingError.keyNotFound(let key, _) {
            #expect(key.stringValue == "path")
        }
        #expect(throws: DecodingError.self) { try decode(String(minimal.dropLast()) + #", "outline":"future"}"#) }
    }

    @Test func plannableCoverageFollowsUnshaped() throws {
        let json =
            #"{"path":"/a","index":0,"family":"A","style":"Regular","coverage":[[97,122],[1575,1610]],"unshaped":[[1575,1610],[8192,8192]]}"#
        var face = try decode(json)
        #expect(face.unshaped.ranges == [1575...1610] && face.plannableCoverage.ranges == [97...122])
        #expect(face.groupCounts == [.latin: 26] && face.canShape(.arabic))
        face.shapesGroups = []
        #expect(!face.canShape(.arabic) && face.canShape(.latin))
        face.unshaped = .empty
        #expect(face.plannableCoverage == face.coverage)
        face.coverage = CodepointSet(scalarsOf: "xyz")
        face.unshaped = CodepointSet(scalarsOf: "xa")
        #expect(face.unshaped == CodepointSet(scalarsOf: "x"))
        #expect(face.plannableCoverage == CodepointSet(scalarsOf: "yz") && face.groupCounts == [.latin: 2])
    }

    @Test func groupCountsPerFace() {
        let face = FaceRecord(path: "/a", family: "A", coverage: .init(scalarsOf: "ab漢，"))
        #expect(face.count(of: .latin) == 2 && face.count(of: .han) == 1 && face.count(of: .cjkSymbols) == 1)
        #expect(face.count(of: .greek) == 0 && face.groupCounts.count == 3)
    }

    @Test func groupCountsAreValues() {
        let original = FaceRecord(path: "/a", family: "A", coverage: .init(scalarsOf: "ab"))
        var copy = original
        copy.groupCounts[.latin] = 99
        #expect(original.count(of: .latin) == 2 && copy.count(of: .latin) == 99)
    }
}
