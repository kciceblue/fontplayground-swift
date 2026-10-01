import FPCore
import FPEngineClient
import FPMacServices
import Foundation

public enum EngineErrorText {
    public static func reason(_ error: any Error) -> String {
        if let error = error as? EngineError {
            switch error {
            case .helperNotFound: return ShellText.engineMissing
            case .launchFailed: return ShellText.engineLaunchFailed
            case .incompatibleHelper(let reported, let supported):
                return ShellText.engineIncompatible(reported: reported, supported: supported)
            case .timedOut: return ShellText.engineTimedOut
            case .crashed, .interrupted, .protocolViolation: return ShellText.engineStopped
            case .helperFailed(let failure): return failure.message
            }
        }
        if case .engineUnavailable(let reason) = error as? CatalogError { return reason }
        return error.localizedDescription
    }
}

extension EngineErrorText {
    public static func buildFailure(_ error: any Error, materials: [Material]) -> (message: String, detail: String) {
        switch error as? EngineError {
        case .helperFailed(let failure):
            if failure.code == .staleMaterial {
                let message: String
                if let index = failure.materialIndex, materials.indices.contains(index) {
                    message = BuildText.staleMaterial(materials[index].face.displayName)
                } else {
                    message = BuildText.staleUnknown
                }
                return (message, failure.detail ?? "")
            }
            return (
                BuildText.buildError(failure.message.components(separatedBy: .newlines).first ?? failure.message),
                ReportText.failure(message: failure.message, detail: failure.detail ?? "")
            )
        case .crashed(_, _, let tail), .interrupted(_, _, let tail), .protocolViolation(_, let tail):
            return (BuildText.buildError(BuildText.engineStopped), tail)
        case .timedOut(_, let tail): return (BuildText.buildError(BuildText.timedOut), tail)
        default: return (BuildText.buildError(reason(error) + "."), String(describing: error))
        }
    }
}
