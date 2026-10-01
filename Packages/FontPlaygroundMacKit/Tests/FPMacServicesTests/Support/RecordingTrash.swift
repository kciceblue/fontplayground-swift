import Foundation
import os

@testable import FPMacServices

final class RecordingTrash: TrashCan, Sendable {
    struct State { var failures: Set<String> = []; var moves: [(URL, URL)] = [] }
    private let state = OSAllocatedUnfairLock(initialState: State())
    let directory: URL
    init(directory: URL) { self.directory = directory }
    var moves: [(URL, URL)] { state.withLock { $0.moves } }
    func fail(_ names: Set<String>) { state.withLock { $0.failures = names } }
    func moveToTrash(_ url: URL) throws -> URL? {
        try state.withLock { state in
            if state.failures.contains(url.lastPathComponent) { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var target = directory.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                target = target.appendingPathExtension(UUID().uuidString)
            }
            try FileManager.default.moveItem(at: url, to: target)
            state.moves.append((url, target))
            return target
        }
    }
}
