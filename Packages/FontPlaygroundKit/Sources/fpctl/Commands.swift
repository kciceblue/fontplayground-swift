import FPCore
import FPEngineClient
import Foundation

extension FPCTL {
    static func execute(
        _ invocation: Invocation, environment: [String: String], handle: EngineHandle,
        output: CommandOutput, document: RecipeDocument?
    ) async throws -> Int32 {
        switch invocation.command {
        case .help, .version: return 0
        case .hello(let json):
            let hello = try await handle.engine.hello()
            if json {
                try output.json(hello)
            } else {
                output.out(
                    "fpengine \(hello.fpengineVersion) · protocol \(hello.protocolVersion) · Python \(hello.python) · fontTools \(hello.fonttools) · Unicode \(hello.unicodeVersion) · \(hello.platform)"
                )
                output.out("helper: \(handle.helper)")
            }
            return 0
        case .scan(let paths, let json):
            let result = try await scan(
                FontFolders.files(in: paths), engine: handle.engine, output: output, printFaces: !json)
            if json { try output.json(result) }
            output.err(
                "Scanned \(result.summary.files) files: \(result.summary.faces) faces, \(result.summary.fileErrors) couldn't be read."
            )
            return 0
        case .forge(_, let destination, let folders, let allowMissing, let json, let quiet):
            let outputDirectory = URL(fileURLWithPath: destination).deletingLastPathComponent()
            if let temporary = handle.temporaryDirectory {
                _ = EngineClient.sweepLeftovers(temporaryDirectory: temporary, outputDirectories: [outputDirectory])
            }
            defer {
                if let temporary = handle.temporaryDirectory {
                    _ = EngineClient.sweepLeftovers(temporaryDirectory: temporary, outputDirectories: [outputDirectory])
                }
            }
            guard let document else { throw CommandStopped() }
            let existing = document.materials.map(\.face.path).filter { FileManager.default.fileExists(atPath: $0) }
            var faces = try await scan(.init(files: existing), engine: handle.engine, output: output).faces.filter {
                !$0.hidden
            }
            var loaded = document.makeRecipe(catalog: FaceCatalog(faces))
            if !loaded.report.unresolved.isEmpty {
                let directories = folders.isEmpty ? FontFolders.defaults(environment: environment) : folders
                output.err(
                    "Looking for \(loaded.report.unresolved.count) missing font(s) in \(directories.count) folder(s)…")
                faces += try await scan(FontFolders.files(in: directories), engine: handle.engine, output: output).faces
                    .filter { !$0.hidden }
                loaded = document.makeRecipe(catalog: FaceCatalog(faces))
            }
            for rule in loaded.report.ignoredRules { output.err("fpctl: ignored recipe rule: \(rule)") }
            if loaded.report.mainOutOfRange {
                output.err("fpctl: recipe main font is out of range; using the first material.")
            }
            for (position, outcome) in loaded.report.outcomes.enumerated() {
                if case .duplicate(let earlier) = outcome {
                    output.err(
                        "fpctl: recipe material \(position + 1) duplicates material \(earlier + 1); kept the first.")
                }
            }
            let unresolved = loaded.report.unresolved
            if !unresolved.isEmpty {
                output.err(allowMissing ? "fpctl: warning: building without:" : "fpctl: can't find these fonts:")
                for identity in unresolved {
                    output.err("  \(identity.family) \(identity.style) (PostScript \(identity.postscriptName ?? "-"))")
                }
                if !allowMissing { return 4 }
            }
            var recipe = loaded.recipe
            if allowMissing {
                for material in recipe.materials where material.availability == .notFound {
                    _ = recipe.remove(material.key)
                }
            }
            try Task.checkCancellation()
            var report: ForgeReport?
            var previousStage: EngineStage?, previousMaterial: Int?
            for try await event in handle.engine.forge(recipe.forgeRequest(outputPath: destination)) {
                switch event {
                case .progress(let progress):
                    if !quiet, progress.stage != previousStage || progress.materialIndex != previousMaterial {
                        output.progress(progress, materialNames: recipe.materials.map(\.face.displayName))
                    }
                    previousStage = progress.stage; previousMaterial = progress.materialIndex
                case .finished(let value): report = value
                }
            }
            try Task.checkCancellation()
            guard let report else { throw CommandStopped() }
            if json {
                try output.json(ForgeResult(report: report, unresolved: unresolved.map(Unresolved.init)))
            } else {
                output.report(report)
            }
            return 0
        }
    }

    static func scan(
        _ input: FontFolders.ScanInput, engine: any EngineRunning, output: CommandOutput,
        printFaces: Bool = false
    ) async throws -> ScanResult {
        try Task.checkCancellation()
        var faces: [FaceRecord] = [], errors = input.errors, summary: ScanSummary?
        for error in input.errors { output.fileError(error) }
        for try await event in engine.scan(files: input.files) {
            switch event {
            case .face(let face): faces.append(face); if printFaces { output.scanFace(face) }
            case .fileError(let error): errors.append(error); output.fileError(error)
            case .finished(let value): summary = value
            case .progress: break
            }
        }
        try Task.checkCancellation()
        guard var summary else { throw CommandStopped() }
        // Folder failures are CLI inputs too; preserve helper counters and add each traversal failure once.
        summary.files += input.errors.count
        summary.fileErrors += input.errors.count
        return ScanResult(faces: faces, fileErrors: errors, summary: summary)
    }
}

struct ScanResult: Encodable {
    let faces: [FaceRecord]
    let fileErrors: [ScanFileError]
    let summary: ScanSummary
    enum CodingKeys: String, CodingKey { case faces, fileErrors = "file_errors", summary }
}
private struct ForgeResult: Encodable {
    let report: ForgeReport
    let unresolved: [Unresolved]
    enum CodingKeys: String, CodingKey { case report, unresolved }
}
private struct Unresolved: Encodable {
    let postscriptName: String?
    let family: String
    let style: String
    init(_ identity: PortableFaceIdentity) {
        postscriptName = identity.postscriptName; family = identity.family; style = identity.style
    }
    enum CodingKeys: String, CodingKey { case postscriptName = "postscript_name", family, style }
    func encode(to encoder: Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        try value.encode(postscriptName, forKey: .postscriptName)
        try value.encode(family, forKey: .family); try value.encode(style, forKey: .style)
    }
}
