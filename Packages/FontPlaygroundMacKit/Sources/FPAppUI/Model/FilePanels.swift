import AppKit
import UniformTypeIdentifiers

public struct SavePanelRequest: Equatable, Sendable {
    public var suggestedFileName: String
    public var directory: URL
    public var message: String?
    public var allowedExtension: String
    public init(suggestedFileName: String, directory: URL, message: String? = nil, allowedExtension: String = "ttf") {
        self.suggestedFileName = suggestedFileName; self.directory = directory; self.message = message;
        self.allowedExtension = allowedExtension
    }
}
public struct FolderPanelRequest: Equatable, Sendable {
    public var prompt: String
    public var message: String
    public init(prompt: String, message: String) { self.prompt = prompt; self.message = message }
}
@MainActor public protocol FilePanels: AnyObject {
    func chooseSaveLocation(_ request: SavePanelRequest) async -> URL?
    func chooseFolders(_ request: FolderPanelRequest) async -> [URL]
}
@MainActor final class LiveFilePanels: FilePanels {
    func chooseSaveLocation(_ request: SavePanelRequest) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: request.allowedExtension)!]
        panel.nameFieldStringValue = request.suggestedFileName; panel.directoryURL = request.directory
        panel.message = request.message ?? ""; panel.canCreateDirectories = true; panel.isExtensionHidden = false
        let response: NSApplication.ModalResponse
        if let window = NSApp.mainWindow ?? NSApp.keyWindow {
            response = await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }
    func chooseFolders(_ request: FolderPanelRequest) async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false; panel.prompt = request.prompt; panel.message = request.message
        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.urls : []
    }
}
