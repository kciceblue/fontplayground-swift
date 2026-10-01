import Foundation
import os

final class FontNameIndex: Sendable {
    private struct State { var fingerprint: [String]?; var entries: [FontNameEntry] = [] }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let source: SystemFontNameSource
    init(source: SystemFontNameSource) { self.source = source }
    func entries() -> [FontNameEntry] {
        let fingerprint = source.fingerprint()
        return state.withLock { state in
            if state.fingerprint != fingerprint {
                state.entries = source.nameEntries(); state.fingerprint = fingerprint
            }
            return state.entries
        }
    }
    func invalidate() { state.withLock { $0.fingerprint = nil } }
}
