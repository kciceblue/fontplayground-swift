import CoreText
import FPCore
import FPMacServices
import Foundation
import os

@MainActor final class RowFontCache {
    private struct Key: Hashable { let face: FaceKey; let size: CGFloat }
    private struct Entry { let font: CTFont; var used: UInt64 }
    private let renderer: any FontRendering
    private let capacity: Int
    private let budget: Duration
    private var entries: [Key: Entry] = [:]
    private var failures: Set<Key> = []
    private var pending: [(Key, FaceRecord)] = []
    private var queued: Set<Key> = []
    private var tick: UInt64 = 0
    private var started: ContinuousClock.Instant?
    private var drainTask: Task<Void, Never>?
    private let signposter = OSSignposter(subsystem: "io.github.kciceblue.fontplayground", category: "Picker")
    var onFontsReady: (Set<FaceKey>) -> Void = { _ in }

    init(renderer: any FontRendering, capacity: Int = 512, budgetPerTurn: Duration = .milliseconds(8)) {
        self.renderer = renderer; self.capacity = max(1, capacity); budget = budgetPerTurn
    }
    func font(for face: FaceRecord, size: CGFloat) -> CTFont? {
        let key = Key(face: face.key, size: size)
        tick &+= 1
        if var entry = entries[key] { entry.used = tick; entries[key] = entry; return entry.font }
        guard !failures.contains(key) else { return nil }
        if started == nil { started = .now }
        scheduleDrain()
        if started!.duration(to: .now) < budget {
            queued.remove(key); pending.removeAll { $0.0 == key }
            return create(key, face: face)
        }
        enqueue(key, face: face, preferred: true)
        return nil
    }
    func prefetch(_ faces: [FaceRecord], sizes: [CGFloat]) {
        for face in faces {
            for size in sizes { enqueue(Key(face: face.key, size: size), face: face, preferred: false) }
        }
        if !pending.isEmpty { scheduleDrain() }
    }
    private func enqueue(_ key: Key, face: FaceRecord, preferred: Bool) {
        guard entries[key] == nil, !failures.contains(key) else { return }
        if queued.insert(key).inserted {
            if preferred { pending.insert((key, face), at: 0) } else { pending.append((key, face)) }
        }
    }
    private func create(_ key: Key, face: FaceRecord) -> CTFont? {
        let interval = signposter.beginInterval("RowFonts")
        defer { signposter.endInterval("RowFonts", interval) }
        do {
            let font = try renderer.font(for: .init(face: face, pointSize: key.size)).ctFont
            tick &+= 1; entries[key] = Entry(font: font, used: tick)
            if entries.count > capacity, let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key {
                entries.removeValue(forKey: oldest)
            }
            return font
        } catch {
            failures.insert(key)
            NSLog("Picker font unavailable at %@#%d: %@", face.path, face.index, String(describing: error))
            return nil
        }
    }
    private func scheduleDrain() {
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.drainTask = nil; self.started = .now
            let interval = self.signposter.beginInterval("RowFonts")
            var ready: Set<FaceKey> = []
            while !self.pending.isEmpty, self.started!.duration(to: .now) < self.budget {
                let (key, face) = self.pending.removeFirst(); self.queued.remove(key)
                _ = self.create(key, face: face); ready.insert(key.face)
            }
            self.signposter.endInterval("RowFonts", interval)
            self.onFontsReady(ready)
            if !self.pending.isEmpty { self.scheduleDrain() } else { self.started = nil }
        }
    }
    func removeAll() {
        drainTask?.cancel(); drainTask = nil; entries = [:]; failures = []; pending = []; queued = []; started = nil
    }
}
