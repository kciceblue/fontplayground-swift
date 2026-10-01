import CoreText
import Foundation

// S7: descriptors are immutable and shared safely between render requests.
public struct LastResort: @unchecked Sendable {
    public let descriptor: CTFontDescriptor
    public static let shared: LastResort = .make()

    static func make(fileURL: URL = MacServicesConstants.lastResortURL) -> LastResort {
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fileURL as CFURL) as? [CTFontDescriptor] ?? []
        if let descriptor = descriptors.first(where: {
            CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == "LastResort"
        }) {
            return LastResort(descriptor: descriptor)
        }
        // ADR-0011: this SIP-protected, installed font is the sole name fallback.
        return LastResort(descriptor: CTFontDescriptorCreateWithNameAndSize("LastResort" as CFString, 0))
    }
}
