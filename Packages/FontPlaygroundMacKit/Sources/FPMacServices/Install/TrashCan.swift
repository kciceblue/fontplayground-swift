import Foundation

public protocol TrashCan: Sendable { func moveToTrash(_ url: URL) throws -> URL? }
public struct FinderTrash: TrashCan {
    public init() {}
    public func moveToTrash(_ url: URL) throws -> URL? {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }
}
