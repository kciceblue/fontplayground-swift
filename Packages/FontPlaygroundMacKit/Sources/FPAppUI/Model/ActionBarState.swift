import Foundation

public struct ActionBarState: Equatable {
    public enum Tone: Equatable { case plain, muted, ok, warn, danger }
    public enum LinkKind: Equatable { case showInFinder, openInFontBook, uninstall, notes(Int), details }
    public var status: String; public var tone: Tone
    public var detailLines: [String]
    public var links: [LinkKind]
    public var progress: Double?
    public var showsCancel: Bool; public var cancelEnabled: Bool
    public var showsSaveCopy: Bool; public var saveCopyEnabled: Bool
    public var primaryTitle: String; public var primaryEnabled: Bool; public var primaryIsDone: Bool
    public var namesEditable: Bool

    public static func make(
        problem: String?, engineMissing: Bool, glyphWarning: String?,
        build: BuildControllerSnapshot, licenceLines: [String], fontBookAvailable: Bool,
        home: String
    ) -> Self {
        let busy = build.state.isBusy
        var result = Self(
            status: BuildText.idle, tone: .muted, detailLines: licenceLines, links: [], progress: nil,
            showsCancel: false, cancelEnabled: false, showsSaveCopy: !busy,
            saveCopyEnabled: !busy && problem == nil && !engineMissing,
            primaryTitle: BuildText.install, primaryEnabled: !busy && problem == nil && !engineMissing,
            primaryIsDone: false, namesEditable: !busy)
        switch build.state {
        case .building(let intent, let stage, let fraction, let stopping):
            result.status = BuildText.buildingStatus(StageText.lowerFirst(stage)); result.tone = .plain
            result.detailLines = []; result.progress = fraction; result.showsCancel = true
            result.cancelEnabled = !stopping
            switch intent {
            case .install?: result.primaryTitle = BuildText.installing
            case .save?: result.primaryTitle = BuildText.saving
            case nil: result.primaryTitle = BuildText.building
            }
            return result
        case .installing, .saving:
            result.status = build.state == .installing ? BuildText.installingStatus : BuildText.savingStatus
            result.primaryTitle = build.state == .installing ? BuildText.installing : BuildText.saving
            result.tone = .plain; result.detailLines = []; return result
        default: break
        }
        if engineMissing {
            result.status = BuildText.engineMissing; result.tone = .danger; result.detailLines = []; return result
        }
        if build.installedFullName != nil {
            result.primaryTitle = build.isUpdate ? BuildText.update : BuildText.installed
            result.primaryEnabled = build.isUpdate && problem == nil
            result.primaryIsDone = !build.isUpdate
        }
        if let problem { result.status = problem; result.tone = .danger; result.detailLines = []; return result }
        if build.notice == BuildText.fileGone {
            result.status = BuildText.fileGone; result.tone = .muted; result.detailLines = []; return result
        }
        if build.state == .installed {
            result.status = BuildText.installedStatus(build.installedFullName ?? "")
            result.tone = .ok; result.detailLines = [BuildText.installedDetail] + licenceLines
            if build.hasShownFile { result.links.append(.showInFinder) }
            result.links.append(.uninstall)
            if build.notesCount > 0 { result.links.append(.notes(build.notesCount)) }
        } else if build.state == .saved && build.isFresh {
            result.status = BuildText.savedStatus(ShellText.shortPath(build.savedPath ?? "", home: home));
            result.tone = .ok
            if build.hasShownFile { result.links.append(.showInFinder) }
            if fontBookAvailable { result.links.append(.openInFontBook) }
            if build.notesCount > 0 { result.links.append(.notes(build.notesCount)) }
        } else if case .failed(let message) = build.state {
            result.status = message; result.tone = .danger; result.detailLines = []; result.links = [.details]
        } else if build.state == .cancelled {
            result.status = BuildText.cancelled; result.detailLines = []
        } else if let notice = build.notice {
            result.status = notice; result.detailLines = []
        } else if let glyphWarning {
            result.status = glyphWarning; result.tone = .warn
        }
        return result
    }
}
