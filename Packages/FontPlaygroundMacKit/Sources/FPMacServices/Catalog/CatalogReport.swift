import Foundation

public enum CatalogReport {
    public static func lines(for snapshot: CatalogSnapshot) -> [String] {
        var lines = snapshot.faces.map { face in
            let annotation = snapshot.annotations[face.key]
            var flags: [String] = []
            if annotation?.hiddenFromMenus == true { flags.append("hidden-from-menus") }
            if annotation?.disabledInFontBook == true { flags.append("disabled") }
            if face.isForged { flags.append("forged") }
            return [
                face.family, face.style, face.postscriptName ?? "", annotation?.origin.rawValue ?? "",
                flags.joined(separator: ","), "\(face.path)#\(face.index)",
            ].joined(separator: "\t")
        }
        let c = snapshot.counts
        lines.append(
            "faces=\(c.faces) files=\(c.files) hidden=\(c.hiddenFaces) duplicates=\(c.duplicateFaces) unreadable=\(c.unreadableFiles) skipped=\(c.skippedFiles) disabled=\(c.disabledFaces)"
        )
        return lines
    }
    public static func check(_ snapshot: CatalogSnapshot, menuVisible: Set<String>) -> [String] {
        var problems: [String] = []
        var names: Set<String> = []
        let assets = Set(
            snapshot.faces.filter { $0.path.hasPrefix("/System/Library/AssetsV2/") }.compactMap(\.postscriptName))
        for face in snapshot.faces {
            if face.family.hasPrefix(".") || face.postscriptName?.hasPrefix(".") == true {
                problems.append("Hidden face appears in catalog: \(face.key)")
            }
            if let ps = face.postscriptName {
                if !names.insert(ps).inserted { problems.append("Duplicate PostScript name: \(ps)") }
                if ps.hasPrefix("PingFang"), face.path.hasPrefix("/System/Library/PrivateFrameworks/"),
                    assets.contains(ps)
                {
                    problems.append("Private PingFang duplicates the asset: \(ps)")
                }
            }
        }
        if menuVisible.contains("PingFangSC-Regular"), !names.contains("PingFangSC-Regular") {
            problems.append("Menu-visible PingFang SC is missing.")
        }
        return problems
    }
}
