import CoreText
import Darwin
import FPCore
import Foundation
import os

private struct FontFileStamp: Hashable {
    let path: String
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let seconds: Int
    let nanoseconds: Int

    init(url: URL) throws {
        path = url.standardizedFileURL.path
        var information = stat()
        guard stat(path, &information) == 0 else { throw RenderError.fileMissing(path: path) }
        device = information.st_dev
        inode = information.st_ino
        size = information.st_size
        seconds = information.st_mtimespec.tv_sec
        nanoseconds = information.st_mtimespec.tv_nsec
    }
}

// S7: CTFontDescriptor instances are immutable; this wrapper crosses the cache lock.
private struct FontDescriptors: @unchecked Sendable {
    let values: [CTFontDescriptor]
}

private struct RenderKey: Hashable {
    let stamp: FontFileStamp
    let index: Int
    let postscriptName: String?
    let weight: Int?
    let size: CGFloat
    let axes: [FaceRecord.Axis]
    let built: Bool
}

public final class FontRenderer: FontRendering, @unchecked Sendable {
    // S7: the caches have one lock; all immutable CoreText objects are created outside it.
    private struct State: @unchecked Sendable {
        let descriptors: LRUCache<FontFileStamp, FontDescriptors>
        let fonts: LRUCache<RenderKey, RenderedFont>
    }
    private let state: OSAllocatedUnfairLock<State>
    private let lastResort: LastResort

    public init(lastResort: LastResort = .shared, descriptorCacheCapacity: Int = 512, fontCacheCapacity: Int = 4096) {
        self.lastResort = lastResort
        state = OSAllocatedUnfairLock(
            initialState: State(
                descriptors: LRUCache(capacity: descriptorCacheCapacity), fonts: LRUCache(capacity: fontCacheCapacity)))
    }

    public func font(for request: FaceRenderRequest) throws -> RenderedFont {
        let face = request.face
        let url = URL(fileURLWithPath: face.path).standardizedFileURL
        let stamp = try FontFileStamp(url: url)
        let size = Self.quantized(request.pointSize * request.scale)
        let key = RenderKey(
            stamp: stamp, index: face.index, postscriptName: face.postscriptName,
            weight: request.weight, size: size, axes: face.axes, built: false)
        if let cached = state.withLock({ $0.fonts.value(for: key) }) { return cached }
        let descriptors = try descriptors(at: url, stamp: stamp)
        let descriptor = try resolve(face: face, url: url, descriptors: descriptors)
        var variation: [String: Double] = [:]
        if face.isVariable {
            for axis in face.axes {
                variation[axis.tag] =
                    axis.tag == "wght" && request.weight != nil
                    ? min(max(Double(request.weight!), axis.min), axis.max) : axis.default
            }
        }
        var synthetic: SyntheticBold?
        var note: RenderWeightNote?
        if !face.hasWeightAxis, let weight = request.weight {
            let delta = weight - face.weightClass
            if delta >= 50 {
                let amount = min(delta, 500)
                synthetic = SyntheticBold(
                    delta: amount, strokeWidthPercent: Double(amount) * 0.02,
                    extraAdvance: CGFloat(amount) / 1000 * 0.2 * size)
            } else if delta <= -50 {
                note = .cannotLighten
            }
        }
        return cache(
            makeFont(
                descriptor: descriptor, url: url, size: size, variation: variation,
                synthetic: synthetic, note: note), for: key)
    }

    public func builtFont(at url: URL, pointSize: CGFloat) throws -> RenderedFont {
        let url = url.standardizedFileURL
        let stamp = try FontFileStamp(url: url)
        let size = Self.quantized(pointSize)
        let key = RenderKey(
            stamp: stamp, index: 0, postscriptName: nil, weight: nil,
            size: size, axes: [], built: true)
        if let cached = state.withLock({ $0.fonts.value(for: key) }) { return cached }
        let descriptors = try descriptors(at: url, stamp: stamp)
        guard descriptors.count == 1 else {
            throw RenderError.builtFontInvalid(path: url.path, faceCount: descriptors.count)
        }
        return cache(
            makeFont(
                descriptor: descriptors[0], url: url, size: size,
                variation: [:], synthetic: nil, note: nil), for: key)
    }

    /// The font cache is keyed by the effective size rounded to 1/64 pt, so fonts are built and reported at that
    /// size too; otherwise two requests sharing a key would get whichever size happened to be cached first.
    static func quantized(_ size: CGFloat) -> CGFloat {
        (size * 64).rounded() / 64
    }

    public func hasGlyph(for scalar: Unicode.Scalar, in font: RenderedFont) -> Bool {
        let characters = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        return CTFontGetGlyphsForCharacters(font.ctFont, characters, &glyphs, characters.count) && glyphs[0] != 0
    }

    public func missingScalars(in text: String, for font: RenderedFont) -> [Unicode.Scalar] {
        var seen: Set<Unicode.Scalar> = []
        return text.unicodeScalars.filter {
            $0.value != 0x20 && $0.value != 0x0A && seen.insert($0).inserted && !hasGlyph(for: $0, in: font)
        }
    }

    public func coverage(of font: RenderedFont) -> CodepointSet {
        let bytes = [UInt8](CFCharacterSetCreateBitmapRepresentation(nil, CTFontCopyCharacterSet(font.ctFont)) as Data)
        var ranges: [ClosedRange<UInt32>] = []
        func readPlane(_ plane: UInt32, offset: Int) {
            guard plane <= 16, offset + 8192 <= bytes.count else { return }
            var start: UInt32?
            for bit in 0..<65536 {
                let present = bytes[offset + bit / 8] & (1 << (bit % 8)) != 0
                let codepoint = plane * 65536 + UInt32(bit)
                if present {
                    if start == nil { start = codepoint }
                } else if let lower = start {
                    ranges.append(lower...(codepoint - 1)); start = nil
                }
            }
            if let lower = start { ranges.append(lower...(plane * 65536 + 65535)) }
        }
        readPlane(0, offset: 0)
        var offset = 8192
        while offset + 8193 <= bytes.count {
            readPlane(UInt32(bytes[offset]), offset: offset + 1)
            offset += 8193
        }
        return CodepointSet(ranges: ranges)
    }

    public func invalidate(path: String) {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        state.withLock {
            $0.descriptors.remove { $0.path == path }
            $0.fonts.remove { $0.stamp.path == path }
        }
    }

    public func invalidateAll() {
        state.withLock {
            $0.descriptors.removeAll(); $0.fonts.removeAll()
        }
    }

    private func descriptors(at url: URL, stamp: FontFileStamp) throws -> [CTFontDescriptor] {
        if let cached = state.withLock({ $0.descriptors.value(for: stamp) }) { return cached.values }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
            !descriptors.isEmpty
        else { throw RenderError.unreadable(path: url.path) }
        let result = FontDescriptors(values: descriptors)
        return state.withLock {
            if let existing = $0.descriptors.value(for: stamp) { return existing }
            $0.descriptors.insert(result, for: stamp)
            return result
        }.values
    }

    private func resolve(face: FaceRecord, url: URL, descriptors: [CTFontDescriptor]) throws -> CTFontDescriptor {
        if let name = face.postscriptName {
            let matches = descriptors.filter {
                CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == name
            }
            if let match = matches.first(where: { CTFontDescriptorCopyAttribute($0, kCTFontVariationAttribute) == nil })
                ?? matches.first
            {
                return match
            }
        }
        let handle = try? FileHandle(forReadingFrom: url)
        defer { try? handle?.close() }
        let header = (try? handle?.read(upToCount: 12)) ?? Data()
        if header.prefix(4) == Data("ttcf".utf8) {
            // NATIVE-M2: named variable instances expand descriptor counts, so position is unsafe then.
            if header.count == 12 {
                let count = header.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                if descriptors.count == Int(count), descriptors.indices.contains(face.index) {
                    return descriptors[face.index]
                }
            }
        } else if face.index == 0 {
            return descriptors[0]
        }
        throw RenderError.faceNotFound(path: url.path, index: face.index, postscriptName: face.postscriptName)
    }

    private func makeFont(
        descriptor: CTFontDescriptor, url: URL, size: CGFloat,
        variation: [String: Double], synthetic: SyntheticBold?, note: RenderWeightNote?
    ) -> RenderedFont {
        var attributes: [String: Any] = [
            kCTFontCascadeListAttribute as String: [lastResort.descriptor],
            // NATIVE-M3: supplying defaults alone does not disable automatic optical sizing.
            kCTFontOpticalSizeAttribute as String: "none",
        ]
        if !variation.isEmpty {
            attributes[kCTFontVariationAttribute as String] = Dictionary(
                uniqueKeysWithValues: variation.map {
                    (NSNumber(value: $0.key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }), $0.value)
                })
        }
        let pinned = CTFontDescriptorCreateCopyWithAttributes(descriptor, attributes as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(pinned, size, nil)
        return RenderedFont(
            ctFont: font, fileURL: url, postscriptName: CTFontCopyPostScriptName(font) as String,
            pointSize: size, variation: variation, syntheticBold: synthetic, weightNote: note)
    }

    private func cache(_ font: RenderedFont, for key: RenderKey) -> RenderedFont {
        state.withLock {
            if let existing = $0.fonts.value(for: key) { return existing }
            $0.fonts.insert(font, for: key)
            return font
        }
    }
}
