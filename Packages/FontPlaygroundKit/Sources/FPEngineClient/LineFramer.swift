import Foundation

struct LineFramer {
    enum Error: Swift.Error { case lineTooLong }
    static let maximumLineBytes = 32 * 1024 * 1024
    private var buffer = Data()
    private var readIndex = 0
    private var scanIndex = 0
    var hasPartialLine: Bool { readIndex < buffer.count }

    mutating func append<D: DataProtocol>(_ chunk: D) throws -> [Data] {
        buffer.append(contentsOf: chunk)
        var lines: [Data] = []
        while scanIndex < buffer.count {
            if buffer[scanIndex] == 10 {
                if scanIndex - readIndex > Self.maximumLineBytes { throw Error.lineTooLong }
                if scanIndex > readIndex { lines.append(buffer.subdata(in: readIndex..<scanIndex)) }
                readIndex = scanIndex + 1
            } else if scanIndex - readIndex >= Self.maximumLineBytes {
                throw Error.lineTooLong
            }
            scanIndex += 1
        }
        if readIndex > buffer.count / 2 {
            buffer = Data(buffer.dropFirst(readIndex))
            scanIndex -= readIndex
            readIndex = 0
        }
        return lines
    }

    mutating func finish() -> Data? {
        let partial = hasPartialLine ? buffer.subdata(in: readIndex..<buffer.count) : nil
        buffer.removeAll(keepingCapacity: false)
        readIndex = 0
        scanIndex = 0
        return partial
    }
}
