import Foundation

@testable import FPMacServices

final class FakeRegistry: SystemFontRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var _files: [RegisteredFontFile] = []
    private var _menuVisible: Set<String> = []
    private var _faces: [RegisteredFaceInfo] = []
    private var _calls: [String] = []
    var files: [RegisteredFontFile] {
        get { lock.withLock { _files } }
        set { lock.withLock { _files = newValue } }
    }
    var menuVisible: Set<String> {
        get { lock.withLock { _menuVisible } }
        set { lock.withLock { _menuVisible = newValue } }
    }
    var faces: [RegisteredFaceInfo] {
        get { lock.withLock { _faces } }
        set { lock.withLock { _faces = newValue } }
    }
    var calls: [String] { lock.withLock { _calls } }
    func resetCalls() { lock.withLock { _calls = [] } }
    func registeredFontFiles() -> [RegisteredFontFile] {
        lock.withLock {
            _calls.append("files"); return _files
        }
    }
    func menuVisiblePostScriptNames() -> Set<String> {
        lock.withLock {
            _calls.append("menu"); return _menuVisible
        }
    }
    func registeredFaces(includeDisabled: Bool) -> [RegisteredFaceInfo] {
        lock.withLock {
            _calls.append("faces"); return includeDisabled ? _faces : _faces.filter(\.enabled)
        }
    }
}
struct PrefixFilteredRegistry: SystemFontRegistry {
    var folder: URL
    private let base = CoreTextFontRegistry()
    func registeredFontFiles() -> [RegisteredFontFile] {
        base.registeredFontFiles().filter { DiscoveredFileStamp.inside(URL(fileURLWithPath: $0.path), folder: folder) }
    }
    func menuVisiblePostScriptNames() -> Set<String> {
        base.menuVisiblePostScriptNames().intersection(registeredFontFiles().flatMap(\.postscriptNames))
    }
    func registeredFaces(includeDisabled: Bool) -> [RegisteredFaceInfo] {
        base.registeredFaces(includeDisabled: includeDisabled).filter {
            $0.path.map { DiscoveredFileStamp.inside(URL(fileURLWithPath: $0), folder: folder) } ?? false
        }
    }
}
