import FPCore
import Foundation
import Testing

struct ProtocolTypesTests {
    private func makeSpec() -> ForgeSpec {
        ForgeSpec(
            materials: [
                .init(path: "/fonts/a.ttf"),
                .init(path: "/fonts/b.otf", weight: 500, scale: 0.9),
            ],
            scriptRules: [.han: 1]
        )
    }

    @Test func forgeRequestHasContractShape() throws {
        var spec = makeSpec()
        spec.materials[0].expect = .init(size: 123, mtime: 1_790_000_000.123456)
        spec.familyName = "合体测试"
        let request = ForgeRequest(spec: spec, outputPath: "/builds/font.ttf")
        let data = try request.encodedJSON()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["spec", "output_path"])
        #expect(object["output_path"] as? String == "/builds/font.ttf")
        let encodedSpec = try #require(object["spec"] as? [String: Any])
        #expect(
            Set(encodedSpec.keys) == [
                "materials", "base_index", "script_rules", "default_weight", "default_scale",
                "family_name", "style_name",
            ]
        )
        #expect(encodedSpec["base_index"] as? Int == 0)
        #expect(encodedSpec["default_weight"] is NSNull)
        #expect(encodedSpec["default_scale"] as? Double == 1)
        #expect(encodedSpec["family_name"] as? String == "合体测试")
        #expect(encodedSpec["style_name"] as? String == "Regular")
        let materials = try #require(encodedSpec["materials"] as? [[String: Any]])
        #expect(materials.count == 2)
        #expect(Set(materials[0].keys) == ["path", "index", "weight", "scale", "expect"])
        #expect(Set(materials[1].keys) == ["path", "index", "weight", "scale"])
        #expect(materials[0]["weight"] is NSNull)
        #expect(materials[0]["scale"] is NSNull)
        #expect(materials[1]["weight"] as? Int == 500)
        #expect(materials[1]["scale"] as? Double == 0.9)
        let expect = try #require(materials[0]["expect"] as? [String: Any])
        #expect(Set(expect.keys) == ["postscript_name", "size", "mtime"])
        #expect(expect["postscript_name"] is NSNull)
        #expect(expect["size"] as? Int == 123)
        #expect(expect["mtime"] as? Double == spec.materials[0].expect?.mtime)
        let rules = try #require(encodedSpec["script_rules"] as? [String: Any])
        #expect(rules.count == 15)
        #expect(Set(rules.keys) == Set(ScriptGroup.allCases.map(\.rawValue)))
        for group in ScriptGroup.allCases {
            if group == .han {
                #expect(rules[group.rawValue] as? Int == 1)
            } else {
                #expect(rules[group.rawValue] is NSNull)
            }
        }
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\\/"))
        #expect(json.hasPrefix(#"{"output_path":"/builds/font.ttf","spec":{"base_index":0,"#))
        #expect(try JSONDecoder().decode(ForgeRequest.self, from: data) == request)
    }

    @Test func forgeSpecJSONRoundTrip() throws {
        let source = Data(
            #"""
            {
                "materials": [
                    {"path": "/fonts/a.ttf", "index": 0, "weight": null, "scale": null},
                    {"path": "/fonts/b.otf", "index": 0, "weight": 500, "scale": 0.9}
                ],
                "base_index": 0, "script_rules": {"han": 1, "latin": null, "future_group": 7},
                "default_weight": null, "default_scale": 1.0,
                "family_name": "Forged", "style_name": "Regular", "future_field": {"v": 2}
            }
            """#.utf8
        )
        let spec = try JSONDecoder().decode(ForgeSpec.self, from: source)
        #expect(spec == makeSpec())
        #expect(spec.scriptRules == [.han: 1])
        let encoded = try JSONEncoder().encode(spec)
        #expect(try JSONDecoder().decode(ForgeSpec.self, from: encoded) == spec)
        // Q3: the wire model preserves materials; resolution belongs to WP-305.
        #expect(spec.materials.map(\.path) == ["/fonts/a.ttf", "/fonts/b.otf"])
        #expect(spec.materials[1].weight == 500)
    }

    @Test func forgeSpecDecodesDefaultsAndExpectation() throws {
        let minimal = try JSONDecoder().decode(ForgeSpec.self, from: Data(#"{"materials":[]}"#.utf8))
        #expect(minimal == ForgeSpec())
        let expectation = ForgeSpec.Expectation(postscriptName: "Fixture-Regular", size: 1234, mtime: 17.123456789)
        var spec = makeSpec()
        spec.materials[1].expect = expectation
        let encoded = try JSONEncoder().encode(spec)
        #expect(try JSONDecoder().decode(ForgeSpec.self, from: encoded).materials[1].expect == expectation)
    }

    @Test func forgeReportDecodesContractExample() throws {
        let source = Data(
            #"""
            {
                "output_path": "/builds/forged.ttf", "family_name": "Fixture Forged", "style_name": "Book",
                "postscript_name": "FixtureForged-Book-FP12345678", "full_name": "Fixture Forged Book",
                "total_codepoints": 7, "total_glyphs": 9, "fs_type": 4,
                "materials": [
                    {"name": "Fixture A Regular", "path": "/fonts/a.ttf", "index": 2, "codepoints": 5,
                     "groups": ["latin", "future_group"], "warnings": ["Material warning"]}
                ],
                "issues": [
                    {"code": "future_warning", "severity": "warning", "material_index": 0,
                     "group": "future_group", "message": "A warning"},
                    {"code": "future_error", "severity": "error", "material_index": null,
                     "group": null, "message": "An error"}
                ],
                "licence_notes": [{"class": "apple-sla", "material_indexes": [0], "text": "Licence note"}],
                "warnings": ["General warning"], "duration_s": 1.234, "future_field": true
            }
            """#.utf8
        )
        let report = try JSONDecoder().decode(ForgeReport.self, from: source)
        let expected = ForgeReport(
            outputPath: "/builds/forged.ttf", familyName: "Fixture Forged", styleName: "Book",
            postscriptName: "FixtureForged-Book-FP12345678", fullName: "Fixture Forged Book",
            totalCodepoints: 7, totalGlyphs: 9, fsType: 4,
            materials: [
                .init(
                    name: "Fixture A Regular", path: "/fonts/a.ttf", index: 2, codepoints: 5,
                    groups: ["latin", "future_group"], warnings: ["Material warning"]
                )
            ],
            issues: [
                .init(
                    code: "future_warning", severity: .warning, materialIndex: 0, group: "future_group",
                    message: "A warning"),
                .init(code: "future_error", severity: .error, message: "An error"),
            ],
            licenceNotes: [.init(licenceClass: "apple-sla", materialIndexes: [0], text: "Licence note")],
            warnings: ["General warning"], durationSeconds: 1.234
        )
        #expect(report == expected)
        #expect(try JSONDecoder().decode(ForgeReport.self, from: JSONEncoder().encode(report)) == report)

        let minimal = try JSONDecoder().decode(
            ForgeReport.self,
            from: Data(#"{"output_path":"/builds/minimal.ttf","total_codepoints":3,"total_glyphs":4}"#.utf8)
        )
        #expect(minimal == ForgeReport(outputPath: "/builds/minimal.ttf", totalCodepoints: 3, totalGlyphs: 4))
        #expect(minimal.familyName.isEmpty && minimal.styleName.isEmpty)
        #expect(minimal.postscriptName.isEmpty && minimal.fullName.isEmpty)
        #expect(minimal.materials.isEmpty && minimal.issues.isEmpty && minimal.licenceNotes.isEmpty)
        #expect(minimal.warnings.isEmpty && minimal.fsType == nil && minimal.durationSeconds == nil)
    }

    @Test func forgeReportEncodesContractKeysAndExplicitIssueNulls() throws {
        let report = ForgeReport(
            outputPath: "/builds/font.ttf", totalCodepoints: 3, totalGlyphs: 4,
            issues: [.init(code: "warning", severity: .warning, message: "A report warning")],
            licenceNotes: [.init(licenceClass: "unknown", materialIndexes: [0, 1], text: "Unknown licence")]
        )
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        #expect(
            Set(object.keys) == [
                "output_path", "family_name", "style_name", "postscript_name", "full_name", "total_codepoints",
                "total_glyphs", "fs_type", "materials", "issues", "licence_notes", "warnings", "duration_s",
            ]
        )
        let issues = try #require(object["issues"] as? [[String: Any]])
        #expect(Set(issues[0].keys) == ["code", "severity", "material_index", "group", "message"])
        #expect(issues[0]["material_index"] is NSNull && issues[0]["group"] is NSNull)
        let notes = try #require(object["licence_notes"] as? [[String: Any]])
        #expect(Set(notes[0].keys) == ["class", "material_indexes", "text"])
        #expect(notes[0]["class"] as? String == "unknown")
        #expect(notes[0]["material_indexes"] as? [Int] == [0, 1])
    }

    @Test func resolvedWeightAndScale() {
        var spec = makeSpec()
        #expect(spec.resolvedWeight(0) == nil && spec.resolvedWeight(1) == 500)
        #expect(spec.resolvedScale(0) == 1.0 && spec.resolvedScale(1) == 0.9)
        spec.defaultWeight = 300
        #expect(spec.resolvedWeight(0) == 300)
    }

    @Test func requiredReportAndRequestFieldsRejectMissingValues() throws {
        for field in ["output_path", "total_codepoints", "total_glyphs"] {
            var object: [String: Any] = ["output_path": "/builds/font.ttf", "total_codepoints": 3, "total_glyphs": 4]
            object.removeValue(forKey: field)
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(ForgeReport.self, from: data) }
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ForgeSpec.self, from: Data("{}".utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ForgeRequest.self, from: Data(#"{"spec":{"materials":[]}}"#.utf8))
        }
    }
}
