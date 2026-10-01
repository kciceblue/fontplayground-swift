import Foundation

public enum CacheSweeper {
    @discardableResult public static func sweepBuilds(
        _ directory: URL, olderThan age: TimeInterval = 600, now: Date = Date()
    ) -> Int {
        do {
            let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
            let children = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys))
            var count = 0
            for url in children
            where url.lastPathComponent.hasPrefix("forged-") && url.lastPathComponent.hasSuffix(".ttf") {
                let values = try url.resourceValues(forKeys: keys)
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                    let date = values.contentModificationDate, now.timeIntervalSince(date) > age
                else { continue }
                do { try FileManager.default.removeItem(at: url); count += 1 } catch {
                    AppLog.app.error("Couldn't remove a stale build: \(error.localizedDescription, privacy: .public)")
                }
            }
            return count
        } catch { AppLog.app.error("Couldn't sweep builds: \(error.localizedDescription, privacy: .public)"); return 0 }
    }
}
