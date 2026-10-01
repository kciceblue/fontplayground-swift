import Foundation

struct StderrRing {
    private let capacity: Int
    private var bytes = Data()
    init(capacity: Int) { self.capacity = max(0, capacity) }
    var tail: String { String(decoding: bytes, as: UTF8.self) }
    var byteCount: Int { bytes.count }
    mutating func append<D: DataProtocol>(_ data: D) {
        if data.count >= capacity {
            bytes = Data(data.suffix(capacity))
        } else {
            let excess = bytes.count + data.count - capacity
            if excess > 0 { bytes = Data(bytes.dropFirst(excess)) }
            bytes.append(contentsOf: data)
        }
    }
}
