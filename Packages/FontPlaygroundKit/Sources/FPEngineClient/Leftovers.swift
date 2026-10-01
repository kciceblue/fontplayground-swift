import Foundation

enum Leftovers {
    static func remove(
        temporaryDirectory: URL?, outputDirectories: [URL], pid: Int32? = nil, now: Date = Date(),
        fileManager: FileManager = .default, log: (@Sendable (String) -> Void)? = nil
    ) -> Int {
        let directories =
            (temporaryDirectory.map { [($0, "^fpengine-([0-9]+)-")] } ?? [])
            + outputDirectories.map { ($0, "^\\.fpengine-([0-9]+)-.*\\.partial\\.ttf$") }
        var removed = 0
        for (directory, pattern) in directories {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let entries: [URL]
            do {
                entries = try fileManager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
                )
            } catch {
                if fileManager.fileExists(atPath: directory.path) {
                    report("cannot list \(directory.path): \(error)", log)
                }
                continue
            }
            for entry in entries {
                let name = entry.lastPathComponent
                guard let match = expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                    let range = Range(match.range(at: 1), in: name), let entryPID = Int32(name[range])
                else { continue }
                if let pid {
                    guard pid == entryPID else { continue }
                } else {
                    let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate
                    guard !Signals.isAlive(entryPID) || modified.map({ now.timeIntervalSince($0) > 86_400 }) == true
                    else {
                        continue
                    }
                }
                do { try fileManager.removeItem(at: entry); removed += 1 } catch {
                    report("cannot remove \(entry.path): \(error)", log)
                }
            }
        }
        return removed
    }

    private static func report(_ message: String, _ log: (@Sendable (String) -> Void)?) {
        let line = "[EngineClient] \(message)"
        if let log { log(line) } else { try? FileHandle.standardError.write(contentsOf: Data((line + "\n").utf8)) }
    }
}
