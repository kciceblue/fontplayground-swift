import FPCore
import FPEngineClient
import Foundation

struct CommandOutput: Sendable {
    var out: @Sendable (String) -> Void
    var err: @Sendable (String) -> Void
    func json<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        out(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
    func scanFace(_ face: FaceRecord) {
        let groups = ScriptGroup.allCases.filter { (face.groupCounts[$0] ?? 0) > 0 }.map(\.rawValue).joined(
            separator: ",")
        var line =
            "\(face.path)#\(face.index)\t\(face.postscriptName ?? "-")\t\(face.displayName)\t\(face.coverage.count) characters\t\(groups)"
        if !face.supported { line += "\t[unsupported: \(face.unsupportedReason ?? "")]" }
        if face.hidden { line += "\t[hidden]" }
        out(line)
    }
    func fileError(_ error: ScanFileError) {
        err("fpctl: \(error.path): \(error.message) (\(error.code.rawValue))")
    }
    func report(_ value: ForgeReport) {
        out("Output: \(value.outputPath)")
        out("Font: \(value.fullName) (PostScript \(value.postscriptName))")
        out("Characters: \(value.totalCodepoints)   Glyphs: \(value.totalGlyphs)")
        for material in value.materials {
            out("")
            let groups = material.groups.map { ScriptGroup(rawValue: $0).map(EnglishText.groupLabel) ?? $0 }
            out(
                "\(material.name): \(material.codepoints) characters  [\(groups.isEmpty ? "-" : groups.joined(separator: ", "))]"
            )
            for warning in material.warnings { out("    warning: \(warning)") }
        }
        if !value.warnings.isEmpty {
            out(""); out("Warnings:")
            for warning in value.warnings { out("  - \(warning)") }
        }
        if !value.licenceNotes.isEmpty {
            out(""); out("Licence:")
            for note in value.licenceNotes { out("  - \(note.text)") }
        }
        if let seconds = value.durationSeconds { out(String(format: "Built in %.1f s.", seconds)) }
    }
    func progress(_ value: EngineProgress, materialNames: [String]) {
        let text: String
        switch value.stage {
        case .validate: text = "Checking the fonts…"
        case .plan: text = "Deciding which font supplies each character…"
        case .prepare:
            let name =
                value.materialIndex.flatMap { materialNames.indices.contains($0) ? materialNames[$0] : nil } ?? "font"
            text = "Preparing \(name)…"
        case .merge: text = "Combining the fonts…"
        case .finish: text = "Finishing the font…"
        case .verify: text = "Checking the result…"
        case .done: text = "Done."
        case .scan: text = "Reading fonts…"
        }
        err(String(format: "[%3d%%] %@", Int((value.fraction * 100).rounded()), text))
    }
}
