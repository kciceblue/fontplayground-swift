/// Callers serialize access. Weak backward links avoid retaining an evicted list.
final class LRUCache<Key: Hashable, Value> {
    private final class Node {
        let key: Key
        var value: Value
        weak var previous: Node?
        var next: Node?
        init(key: Key, value: Value) { self.key = key; self.value = value }
    }

    private let capacity: Int
    private var nodes: [Key: Node] = [:]
    private var first: Node?
    private var last: Node?

    init(capacity: Int) { self.capacity = max(0, capacity) }

    func value(for key: Key) -> Value? {
        guard let node = nodes[key] else { return nil }
        unlink(node)
        prepend(node)
        return node.value
    }

    func insert(_ value: Value, for key: Key) {
        guard capacity > 0 else { return }
        if let existing = nodes[key] {
            existing.value = value
            unlink(existing)
            prepend(existing)
            return
        }
        let node = Node(key: key, value: value)
        nodes[key] = node
        prepend(node)
        if nodes.count > capacity, let oldest = last {
            unlink(oldest)
            nodes.removeValue(forKey: oldest.key)
        }
    }

    func remove(where predicate: (Key) -> Bool) {
        for key in nodes.keys.filter(predicate) {
            if let node = nodes.removeValue(forKey: key) { unlink(node) }
        }
    }

    func removeAll() { nodes.removeAll(); first = nil; last = nil }

    private func unlink(_ node: Node) {
        if let previous = node.previous { previous.next = node.next } else { first = node.next }
        if let next = node.next { next.previous = node.previous } else { last = node.previous }
        node.previous = nil
        node.next = nil
    }

    private func prepend(_ node: Node) {
        node.next = first
        first?.previous = node
        first = node
        if last == nil { last = node }
    }
}
