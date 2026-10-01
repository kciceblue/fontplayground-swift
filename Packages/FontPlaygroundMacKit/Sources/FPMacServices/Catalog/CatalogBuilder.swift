import FPCore
import Foundation

enum CatalogBuilder {
    static func build(
        files: [DiscoveredFile], faces: [String: [FaceRecord]], errors: [String: (code: String, message: String)],
        skipped: [(path: String, reason: SkipReason)], folderIssues: [CatalogIssue], menuVisible: Set<String>,
        registeredFaces: [RegisteredFaceInfo], generation: Int, isComplete: Bool, activity: CatalogActivity
    ) -> CatalogSnapshot {
        var counts = CatalogCounts()
        counts.files = files.count
        counts.unreadableFiles =
            files.filter { errors[$0.path] != nil }.count
            + folderIssues.filter {
                if case .unreadable = $0 { return true }; return false
            }.count
        counts.skippedFiles = skipped.count
        counts.inaccessibleFolders =
            folderIssues.filter {
                if case .noAccess = $0 { return true }; return false
            }.count
        var issues = folderIssues + skipped.map { CatalogIssue.skipped(path: $0.path, reason: $0.reason) }
        for file in files {
            if let error = errors[file.path] {
                issues.append(.unreadable(path: file.path, code: error.code, message: error.message))
            }
        }
        let byIdentity = Dictionary(files.map { ($0.stamp.identity, $0) }, uniquingKeysWith: { first, _ in first })
        var registryByPath: [String: [RegisteredFaceInfo]] = [:]
        var disabledWithoutPath: Set<String> = []
        var disabledNames: Set<String> = []
        for info in registeredFaces {
            if !info.enabled { disabledNames.insert(info.postscriptName) }
            if let path = info.path, let identity = DiscoveredFileStamp(path)?.identity, let file = byIdentity[identity]
            {
                registryByPath[file.path, default: []].append(info)
            } else if info.path == nil && !info.enabled {
                disabledWithoutPath.insert(info.postscriptName)
            }
        }
        struct Candidate {
            var face: FaceRecord
            var file: DiscoveredFile
            var annotation: FaceAnnotation
            var priority: Int
            var registered: Bool
        }
        var candidates: [Candidate] = []
        var matchedDisabled: Set<String> = []
        for file in files {
            for face in faces[file.path] ?? [] {
                if face.hidden { counts.hiddenFaces += 1; continue }
                let name = face.postscriptName
                let infos = registryByPath[file.path, default: []].filter { $0.postscriptName == name }
                let registered = name.map { file.registeredPostscriptNames.contains($0) } ?? false
                let disabled =
                    infos.contains { !$0.enabled }
                    || (name.map { disabledWithoutPath.contains($0) && !registered } ?? false)
                if disabled { counts.disabledFaces += 1 }
                if disabled, let name { matchedDisabled.insert(name) }
                candidates.append(
                    .init(
                        face: face, file: file,
                        annotation: .init(
                            origin: file.origin,
                            hiddenFromMenus: file.origin != .extraFolder
                                && (name.map { !menuVisible.contains($0) } ?? false),
                            disabledInFontBook: disabled), priority: infos.map(\.priority).max() ?? 0,
                        registered: registered))
            }
        }
        func originRank(_ origin: FaceOrigin) -> Int {
            switch origin {
            case .system, .systemAsset: 0;
            case .local: 1;
            case .user: 2;
            case .activated: 3;
            case .extraFolder: 4
            }
        }
        func preferred(_ a: Candidate, _ b: Candidate) -> Bool {
            if a.registered != b.registered { return a.registered }
            if a.priority != b.priority { return a.priority > b.priority }
            if a.annotation.disabledInFontBook != b.annotation.disabledInFontBook {
                return !a.annotation.disabledInFontBook
            }
            let ap = a.file.path.hasPrefix("/System/Library/PrivateFrameworks/")
            let bp = b.file.path.hasPrefix("/System/Library/PrivateFrameworks/")
            if ap != bp { return !ap }
            if originRank(a.file.origin) != originRank(b.file.origin) {
                return originRank(a.file.origin) < originRank(b.file.origin)
            }
            if a.file.path != b.file.path { return a.file.path.utf8.lexicographicallyPrecedes(b.file.path.utf8) }
            return a.face.index < b.face.index
        }
        var winners: [String: Candidate] = [:]
        var unnamed: [Candidate] = []
        var groups: [String: [Candidate]] = [:]
        for candidate in candidates {
            if let name = candidate.face.postscriptName {
                groups[name, default: []].append(candidate)
            } else {
                unnamed.append(candidate)
            }
        }
        for (name, group) in groups {
            let ordered = group.sorted(by: preferred)
            let winner = ordered[0]
            winners[name] = winner
            for loser in ordered.dropFirst() {
                counts.duplicateFaces += 1
                issues.append(.duplicate(kept: winner.face.key, dropped: loser.face.key, postscriptName: name))
            }
        }
        let final = (Array(winners.values) + unnamed).sorted { a, b in
            let family = a.face.family.compare(b.face.family, options: [.caseInsensitive, .numeric], locale: nil)
            if family != .orderedSame { return family == .orderedAscending }
            if a.face.weightClass != b.face.weightClass { return a.face.weightClass < b.face.weightClass }
            if a.face.italic != b.face.italic { return !a.face.italic }
            if a.face.style != b.face.style { return a.face.style < b.face.style }
            if a.face.path != b.face.path { return a.face.path < b.face.path }
            return a.face.index < b.face.index
        }
        for name in disabledNames.subtracting(matchedDisabled) {
            issues.append(.disabledUnlocated(postscriptName: name))
        }
        counts.disabledUnlocated = disabledNames.subtracting(matchedDisabled).count
        counts.faces = final.count
        return CatalogSnapshot(
            generation: generation, faces: final.map(\.face),
            annotations: Dictionary(
                final.map { ($0.face.key, $0.annotation) }, uniquingKeysWith: { first, _ in first }),
            counts: counts, issues: issues.sorted { ($0.sortKey, $0.englishText) < ($1.sortKey, $1.englishText) },
            isComplete: isComplete, activity: activity)
    }
}
