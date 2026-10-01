import FPCore
import FPMacServices
import Foundation

public enum BuildIntent: Equatable, Sendable { case install, save(URL) }
public enum BuildState: Equatable {
    case idle
    case building(intent: BuildIntent?, stage: String, fraction: Double, stopping: Bool)
    case installing, saving, built, installed, saved
    case failed(message: String)
    case cancelled
    public var isBusy: Bool {
        switch self {
        case .building, .installing, .saving: true;
        default: false
        }
    }
}
public struct BuildResult: Equatable {
    public let id: UUID
    public let url: URL
    public let report: ForgeReport
    public let spec: ForgeSpec
}
public struct InstalledRecord: Equatable {
    public var font: InstalledFont
    public var resultID: UUID
}
public struct BuildControllerSnapshot: Equatable {
    public var state: BuildState
    public var isFresh: Bool, isUpdate: Bool
    public var installedFullName: String?
    public var savedPath: String?
    public var hasShownFile: Bool
    public var notice: String?
    public var notesCount: Int
}
