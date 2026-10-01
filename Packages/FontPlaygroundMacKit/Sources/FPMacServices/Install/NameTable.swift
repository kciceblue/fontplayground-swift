import CoreText
import Foundation

public enum NameTableError: Error, Equatable { case malformed }
public struct NameRecord: Hashable, Sendable {
    public var platformID, encodingID, languageID, nameID: UInt16
    public var value: String
}
public struct NameTable: Sendable {
    public let records: [NameRecord]
    public init(data: Data) throws {
        let bytes = Array(data)
        func word(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
        guard bytes.count >= 6, word(0) <= 1, word(4) <= bytes.count else { throw NameTableError.malformed }
        let base = word(4)
        var records: [NameRecord] = []
        for index in 0..<word(2) {
            let offset = 6 + index * 12
            guard offset + 12 <= bytes.count else { break }
            let platform = word(offset); let encoding = word(offset + 2)
            let start = base + word(offset + 10); let length = word(offset + 8)
            guard start <= bytes.count, length <= bytes.count - start else { continue }
            let stringEncoding: String.Encoding
            if platform == 0 || (platform == 3 && [0, 1, 10].contains(encoding)) {
                stringEncoding = .utf16BigEndian
            } else if platform == 1 {
                let mac: CFStringEncoding
                switch encoding {
                case 0: mac = CFStringBuiltInEncodings.macRoman.rawValue
                case 1: mac = CFStringEncoding(CFStringEncodings.macJapanese.rawValue)
                case 2: mac = CFStringEncoding(CFStringEncodings.macChineseTrad.rawValue)
                case 3: mac = CFStringEncoding(CFStringEncodings.macKorean.rawValue)
                case 25: mac = CFStringEncoding(CFStringEncodings.macChineseSimp.rawValue)
                default: continue
                }
                stringEncoding = String.Encoding(
                    rawValue: CFStringConvertEncodingToNSStringEncoding(mac))
            } else {
                continue
            }
            guard let value = String(data: Data(bytes[start..<(start + length)]), encoding: stringEncoding),
                !value.isEmpty
            else { continue }
            records.append(
                .init(
                    platformID: UInt16(platform), encodingID: UInt16(encoding), languageID: UInt16(word(offset + 4)),
                    nameID: UInt16(word(offset + 6)), value: value))
        }
        self.records = records
    }
    public func strings(nameID: UInt16) -> [String] {
        var seen: Set<String> = []
        return records.filter { $0.nameID == nameID }.compactMap { seen.insert($0.value).inserted ? $0.value : nil }
    }
    public func preferred(nameID: UInt16) -> String? {
        let candidates = records.filter { $0.nameID == nameID }
        for (platform, encoding, language): (UInt16, UInt16, UInt16) in [(3, 1, 0x409), (3, 10, 0x409), (1, 0, 0)] {
            if let record = candidates.first(where: {
                $0.platformID == platform && $0.encodingID == encoding && $0.languageID == language
            }) {
                return record.value
            }
        }
        return candidates.first?.value
    }
    public static func tables(forFontAt url: URL) -> [NameTable] {
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        var seen: Set<Data> = []
        return descriptors.compactMap { descriptor in
            let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
            guard let data = CTFontCopyTable(font, CTFontTableTag(kCTFontTableName), []) as Data?,
                seen.insert(data).inserted
            else { return nil }
            return try? NameTable(data: data)
        }
    }
}
