import FPCore
import Foundation

public enum BuildOutputs {
    public static func make(in builds: URL) throws -> URL {
        try FileManager.default.createDirectory(at: builds, withIntermediateDirectories: true)
        return builds.appendingPathComponent("forged-\(UUID().uuidString.lowercased()).ttf")
    }
    public static func delete(_ url: URL, builds: URL) {
        let file = url.standardizedFileURL
        guard file.deletingLastPathComponent().path == builds.standardizedFileURL.path,
            file.lastPathComponent.hasPrefix("forged-"), file.pathExtension == "ttf"
        else {
            NSLog("Refusing to delete a non-build file: %@", url.path); return
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        guard let kind = attributes?[.type] as? FileAttributeType, kind == .typeRegular || kind == .typeSymbolicLink
        else {
            NSLog("Refusing to delete a build directory: %@", file.path); return
        }
        do { try FileManager.default.removeItem(at: file) } catch {
            NSLog("Could not remove build output %@: %@", file.path, error.localizedDescription)
        }
    }
}
public enum SaveCopy {
    public static func request(
        for recipe: Recipe, settings: AppSettings, paths: AppPaths, probe: any FileSystemProbe,
        licenceLines: [String] = []
    ) -> SavePanelRequest {
        let directory: URL
        if let path = settings.lastSaveDirectory, probe.kind(of: path) == .directory {
            directory = URL(fileURLWithPath: path)
        } else {
            directory = paths.documents
        }
        return SavePanelRequest(
            suggestedFileName: recipe.suggestedFileName, directory: directory,
            message: licenceLines.isEmpty ? nil : licenceLines.joined(separator: "\n"))
    }
    public static func enforcingExtension(_ url: URL) -> URL {
        url.pathExtension.lowercased() == "ttf" ? url : url.appendingPathExtension("ttf")
    }
}
