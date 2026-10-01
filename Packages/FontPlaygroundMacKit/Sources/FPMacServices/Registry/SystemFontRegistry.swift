import CoreText
import Foundation

public struct RegisteredFontFile: Hashable, Sendable {
    public var path: String
    public var postscriptNames: [String]
    public init(path: String, postscriptNames: [String]) { self.path = path; self.postscriptNames = postscriptNames }
}
public struct RegisteredFaceInfo: Hashable, Sendable {
    public var postscriptName: String
    public var path: String?
    public var priority: Int
    public var enabled: Bool
    public var familyName: String
    public init(postscriptName: String, path: String?, priority: Int, enabled: Bool, familyName: String = "") {
        self.postscriptName = postscriptName; self.path = path; self.priority = priority; self.enabled = enabled
        self.familyName = familyName
    }
}
public protocol SystemFontRegistry: Sendable {
    func registeredFontFiles() -> [RegisteredFontFile]
    func menuVisiblePostScriptNames() -> Set<String>
    func registeredFaces(includeDisabled: Bool) -> [RegisteredFaceInfo]
}
public struct CoreTextFontRegistry: SystemFontRegistry {
    public init() {}
    public func registeredFontFiles() -> [RegisteredFontFile] {
        files(from: descriptors(includeDisabled: false))
    }
    // Fingerprints need paths, not every face name. Inspect enabled status only once per descriptor.
    func fingerprintSnapshot() -> (paths: [String], disabledNames: [String]) {
        var paths: [String] = []
        var seen: Set<String> = []
        var standardized: [String: String] = [:]
        var disabledNames: [String] = []
        func add(_ url: URL) {
            guard url.isFileURL else { return }
            let path = standardPath(url, cache: &standardized)
            if seen.insert(path).inserted { paths.append(path) }
        }
        for url in CTFontManagerCopyAvailableFontURLs() as? [URL] ?? [] { add(url) }
        for descriptor in descriptors(includeDisabled: true) {
            if (CTFontDescriptorCopyAttribute(descriptor, kCTFontEnabledAttribute) as? NSNumber)?.boolValue == false {
                if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                    disabledNames.append(name)
                }
            } else if let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL {
                add(url)
            }
        }
        return (paths, disabledNames)
    }
    private func files(from descriptors: [CTFontDescriptor]) -> [RegisteredFontFile] {
        var result: [RegisteredFontFile] = []
        var indexes: [String: Int] = [:]
        var paths: [String: String] = [:]
        func add(path: String, name: String?) {
            let index: Int
            if let existing = indexes[path] {
                index = existing
            } else {
                index = result.count; indexes[path] = index; result.append(.init(path: path, postscriptNames: []))
            }
            if let name, !name.isEmpty, !result[index].postscriptNames.contains(name) {
                result[index].postscriptNames.append(name)
            }
        }
        for url in CTFontManagerCopyAvailableFontURLs() as? [URL] ?? [] where url.isFileURL {
            let fragment = url.fragment(percentEncoded: false) ?? ""
            let name =
                fragment.hasPrefix("postscript-name=") ? String(fragment.dropFirst("postscript-name=".count)) : nil
            add(path: standardPath(url, cache: &paths), name: name)
        }
        for descriptor in descriptors {
            if let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL, url.isFileURL {
                add(
                    path: standardPath(url, cache: &paths),
                    name: CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String)
            }
        }
        return result
    }
    public func menuVisiblePostScriptNames() -> Set<String> {
        Set(CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? [])
    }
    public func registeredFaces(includeDisabled: Bool) -> [RegisteredFaceInfo] {
        var paths: [String: String] = [:]
        return descriptors(includeDisabled: includeDisabled).compactMap { descriptor in
            guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else {
                return nil
            }
            let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL
            return .init(
                postscriptName: name, path: url.flatMap { $0.isFileURL ? standardPath($0, cache: &paths) : nil },
                priority: (CTFontDescriptorCopyAttribute(descriptor, kCTFontPriorityAttribute) as? NSNumber)?.intValue
                    ?? 0,
                enabled: (CTFontDescriptorCopyAttribute(descriptor, kCTFontEnabledAttribute) as? NSNumber)?.boolValue
                    ?? true,
                familyName: CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String ?? "")
        }
    }
    private func standardPath(_ url: URL, cache: inout [String: String]) -> String {
        let path = url.path(percentEncoded: false)
        if let cached = cache[path] { return cached }
        let standard = url.standardizedFileURL.path(percentEncoded: false)
        cache[path] = standard
        return standard
    }
    private func descriptors(includeDisabled: Bool) -> [CTFontDescriptor] {
        var options: [CFString: Any] = [kCTFontCollectionDisallowAutoActivationOption: true]
        if includeDisabled { options[kCTFontCollectionIncludeDisabledFontsOption] = true }
        let collection = CTFontCollectionCreateFromAvailableFonts(options as CFDictionary)
        return CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
    }
}
