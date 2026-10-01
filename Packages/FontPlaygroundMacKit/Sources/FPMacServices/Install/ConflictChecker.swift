import Foundation

enum ConflictChecker {
    static func decide(
        query: InstallQuery, entries: [FontNameEntry], ours: (String) -> InstalledFont?,
        fileExists: (String) -> Bool
    ) -> InstallConflict {
        let fold = SystemFontNameSource.fold
        if query.family.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(".")
            || query.postscriptName.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(".")
        {
            return .block(.hiddenName)
        }
        let family = fold(query.family); let fullName = fold(query.fullName); let ps = fold(query.postscriptName)
        let hits = entries.filter { entry in
            if let path = entry.path, !fileExists(path) { return false }
            return entry.familyKeys.contains(family) || entry.fullNameKeys.contains(fullName)
                || fold(entry.postscriptName) == ps
        }
        func reason(_ hits: [FontNameEntry], domain: (String) -> ConflictReason) -> ConflictReason {
            if hits.contains(where: { $0.familyKeys.contains(family) }) { return domain(query.family) }
            if hits.contains(where: { $0.fullNameKeys.contains(fullName) }) { return domain(query.fullName) }
            return .internalNameInUse(postscriptName: query.postscriptName)
        }
        let system = hits.filter { $0.domain == .system }
        if !system.isEmpty { return .block(reason(system) { .systemHas(name: $0) }) }
        let local = hits.filter { $0.domain == .local }
        if !local.isEmpty { return .block(reason(local) { .installedForEveryone(name: $0) }) }
        let foreign = hits.filter { $0.domain == .other || ($0.domain == .user && $0.path.flatMap(ours) == nil) }
        if !foreign.isEmpty { return .block(reason(foreign) { .youHave(name: $0) }) }
        let owned = hits.filter { $0.domain == .user }.compactMap { entry -> (FontNameEntry, InstalledFont)? in
            entry.path.flatMap(ours).map { (entry, $0) }
        }
        for (entry, font) in owned where fold(entry.postscriptName) == ps && fold(font.fullName) != fullName {
            return .block(.internalNameUsedByYourFont(postscriptName: query.postscriptName, fullName: font.fullName))
        }
        let replacements = owned.map(\.1).filter { fold($0.fullName) == fullName }.sorted {
            if $0.installedAt != $1.installedAt { return $0.installedAt > $1.installedAt }
            return $0.fileURL.path.utf8.lexicographicallyPrecedes($1.fileURL.path.utf8)
        }
        if let font = replacements.first { return .replaceOurs(font) }
        if hits.contains(where: { $0.domain == .downloadable }) {
            return .ask(.appleOffersDownload(name: query.family))
        }
        return .noConflict
    }
}
