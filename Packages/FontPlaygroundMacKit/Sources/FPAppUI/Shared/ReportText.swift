import FPCore
import Foundation

public enum ReportText {
    public static func render(
        _ report: ForgeReport,
        groupLabel: (String) -> String = { ScriptGroup(rawValue: $0).map(ModelText.groupLabel) ?? $0 }
    ) -> String {
        var lines = [
            ShellText.reportFont(name: report.fullName)
                + (report.postscriptName.isEmpty ? "" : ShellText.reportPostscript(name: report.postscriptName)),
            ShellText.reportCounts(characters: report.totalCodepoints, glyphs: report.totalGlyphs),
        ]
        if let seconds = report.durationSeconds {
            lines.append(ShellText.reportDuration(seconds: String(format: "%.1f", seconds)))
        }
        if !report.materials.isEmpty { lines.append("") }
        for material in report.materials {
            let groups = material.groups.map(groupLabel).joined(separator: ModelText.listSeparator)
            lines.append(
                ShellText.reportMaterial(
                    name: material.name, count: material.codepoints, groups: material.groups.isEmpty ? "-" : groups))
            lines += material.warnings.map { ShellText.reportWarning(message: $0) }
        }
        if !report.licenceNotes.isEmpty {
            lines += ["", ShellText.licence]
            for note in report.licenceNotes {
                let names = note.materialIndexes.filter { report.materials.indices.contains($0) }.map {
                    report.materials[$0].name
                }.joined(separator: ModelText.listSeparator)
                lines.append("  - " + note.text + (names.isEmpty ? "" : " (" + names + ")"))
            }
        }
        if !report.warnings.isEmpty { lines += ["", ShellText.warnings] + report.warnings.map { "  - " + $0 } }
        return lines.joined(separator: "\n")
    }
    public static func failure(message: String, detail: String) -> String {
        message + (detail.isEmpty ? "" : "\n\n" + detail)
    }
}
