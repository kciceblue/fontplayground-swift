import FPMacServices
import Foundation

/// Only complete catalogs replace the comparison baseline; partial refreshes must not look like removals.
enum CatalogWatch {
    static func run(
        catalog: any FontCataloging, after initial: CatalogSnapshot,
        output: @Sendable (String) -> Void
    ) async -> Bool {
        // Subscribe before observing so the first notification cannot publish into a gap.
        let snapshots = await catalog.snapshots()
        await catalog.startObservingSystemChanges()
        var previous = initial
        for await snapshot in snapshots {
            if Task.isCancelled { break }
            guard snapshot.isComplete else { continue }
            let oldKeys = Set(previous.faces.map(\.key)), newKeys = Set(snapshot.faces.map(\.key))
            for face in snapshot.faces where !oldKeys.contains(face.key) {
                output("+ \(face.family)\t\(face.style)\t\(face.postscriptName ?? "")")
            }
            for face in previous.faces where !newKeys.contains(face.key) {
                output("- \(face.family)\t\(face.style)\t\(face.postscriptName ?? "")")
            }
            previous = snapshot
        }
        await catalog.stopObservingSystemChanges()
        await catalog.cancelRefresh()
        return Task.isCancelled
    }
}
