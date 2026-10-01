import FPCore
import FPEngineClient
import Foundation
import os

struct SelfTestRunner: Sendable {
    let options: SelfTestOptions
    let dependencies: SelfTestDependencies
    let output: @Sendable (String) -> Void

    func run() async -> (summary: SelfTestSummary, exitCode: Int32) {
        let started = ContinuousClock.now
        let state = SelfTestState(options: options, dependencies: dependencies, output: SelfTestOutput(output: output))
        let exitCode: Int32
        do {
            exitCode = try await selfTestDeadline(options.timeout) {
                try await state.prepare()
                return await state.runSteps()
            }
        } catch is SelfTestDeadline {
            exitCode = 4
        } catch {
            SelfTestOutput.error("self-test: couldn't create temporary folder: \(error)")
            exitCode = 3
        }
        await state.finalize(exitCode: exitCode)
        let summary = await state.summary(
            exitCode: exitCode, milliseconds: selfTestMilliseconds(started.duration(to: .now)))
        SelfTestOutput(output: output).summary(summary)
        let failed = summary.failedSteps.isEmpty ? "none" : summary.failedSteps.joined(separator: ",")
        AppLog.selfTest.notice(
            "self-test: \(summary.result, privacy: .public) (failed: \(failed, privacy: .public), \(summary.durationMs) ms)"
        )
        return (summary, exitCode)
    }
}

private actor SelfTestState {
    let options: SelfTestOptions
    let dependencies: SelfTestDependencies
    let output: SelfTestOutput
    var info = BundleInfo(identifier: nil, shortVersion: "", build: "")
    var finalized = false
    var activeStep: (step: SelfTestStep, started: ContinuousClock.Instant)?
    var root: URL?
    var engine: (any EngineRunning)?
    var kind: EngineKind?
    var engineVersion = ""
    var document: RecipeDocument?
    var recipe: Recipe?
    var report: ForgeReport?
    var failed: [String] = []

    init(options: SelfTestOptions, dependencies: SelfTestDependencies, output: SelfTestOutput) {
        self.options = options; self.dependencies = dependencies; self.output = output
    }

    func prepare() async throws {
        let dependencies = dependencies
        let info = try await selfTestDetached { dependencies.bundleInfo() }
        try checkActive(); self.info = info
        let root = try await selfTestDetached {
            let root = try dependencies.temporaryRoot()
            do {
                try Task.checkCancellation()
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent("tmp"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent("out"), withIntermediateDirectories: true)
                try Task.checkCancellation()
                return root
            } catch {
                try? dependencies.removeTemporaryRoot(root)
                throw error
            }
        }
        do {
            try checkActive(); self.root = root
        } catch {
            // A root returned after the deadline belongs only to this run; don't leave it behind.
            _ = try? await selfTestDetached { try dependencies.removeTemporaryRoot(root) }
            throw error
        }
    }

    private func checkActive() throws {
        try Task.checkCancellation()
        if finalized { throw CancellationError() }
    }

    func runSteps() async -> Int32 {
        for step in SelfTestStep.allCases where step != .cleanup {
            let result = await runStep(step)
            if result != 0 { return result }
        }
        return 0
    }

    func finalize(exitCode: Int32) async {
        finalized = true
        if let activeStep {
            failed.append(activeStep.step.rawValue)
            output.step(
                activeStep.step, ok: false,
                milliseconds: selfTestMilliseconds(activeStep.started.duration(to: .now)), detail: [:],
                error: "overall timeout")
            self.activeStep = nil
        }
        guard let root else { return }
        let started = ContinuousClock.now, options = options, dependencies = dependencies
        do {
            // Keep the ten-second watchdog's total return time below twelve seconds, even if cleanup blocks.
            let budget: Duration = exitCode == 4 ? .milliseconds(1500) : .seconds(SelfTestStep.cleanup.budget)
            let detail: [String: String] = try await selfTestDeadline(budget) {
                try await selfTestDetached {
                    if dependencies.injectedFailure == "cleanup" { throw SelfTestFailure("injected") }
                    if options.keepTemporaryFiles { return ["root": root.path] }
                    try dependencies.removeTemporaryRoot(root)
                    return [:]
                }
            }
            output.step(
                .cleanup, ok: true, milliseconds: selfTestMilliseconds(started.duration(to: .now)),
                detail: detail, error: nil)
        } catch {
            output.step(
                .cleanup, ok: false, milliseconds: selfTestMilliseconds(started.duration(to: .now)), detail: [:],
                error: error is SelfTestDeadline ? "cleanup budget exceeded" : String(describing: error))
        }
    }

    private func runStep(_ step: SelfTestStep) async -> Int32 {
        guard !finalized else { return 4 }
        let started = ContinuousClock.now
        activeStep = (step, started)
        do {
            let detail = try await selfTestDeadline(.seconds(step.budget)) { try await self.perform(step) }
            guard !finalized else { return 4 }
            activeStep = nil
            output.step(
                step, ok: true, milliseconds: selfTestMilliseconds(started.duration(to: .now)), detail: detail,
                error: nil)
            return 0
        } catch {
            guard !finalized else { return 4 }
            activeStep = nil
            let failure =
                error is SelfTestDeadline
                ? SelfTestFailure("step budget of \(step.budget) s exceeded") : error as? SelfTestFailure
            failed.append(step.rawValue)
            output.step(
                step, ok: false, milliseconds: selfTestMilliseconds(started.duration(to: .now)),
                detail: failure?.detail ?? [:], error: failure?.description ?? String(describing: error))
            return failure?.exitCode ?? 1
        }
    }

    private func perform(_ step: SelfTestStep) async throws -> [String: String] {
        if dependencies.injectedFailure == step.rawValue { throw SelfTestFailure("injected") }
        try checkActive()
        guard let root else { throw SelfTestFailure("temporary root missing", exitCode: 3) }
        switch step {
        case .environment:
            guard info.identifier == "io.github.kciceblue.fontplayground" else {
                throw SelfTestFailure("incorrect bundle identifier")
            }
            #if arch(arm64)
                return ["architecture": "arm64", "bundle_id": info.identifier ?? ""]
            #else
                throw SelfTestFailure("the app requires arm64")
            #endif
        case .engine:
            do {
                let engineProvider = dependencies.engine
                let resolved = try await selfTestDetached { try engineProvider(root.appendingPathComponent("tmp")) }
                try checkActive()
                engine = resolved.0; kind = resolved.1
            } catch EngineError.helperNotFound {
                throw SelfTestFailure("font engine not found", exitCode: 3)
            }
            if options.requireEmbeddedEngine && kind != .embedded {
                throw SelfTestFailure("an embedded font engine is required", exitCode: 3)
            }
            guard let engine else { throw SelfTestFailure("font engine not found", exitCode: 3) }
            let hello = try await engine.hello()
            try checkActive(); engineVersion = hello.fpengineVersion
            return ["kind": kind?.rawValue ?? "none", "version": engineVersion]
        case .recipe:
            let recipeData = dependencies.recipeData
            let document = try await selfTestDetached { try RecipeDocument.decode(recipeData()) }
            try checkActive(); self.document = document
            return ["materials": String(document.materials.count)]
        case .discover:
            guard let document else { throw SelfTestFailure("recipe missing") }
            let availableFontURLs = dependencies.availableFontURLs
            let paths = try await selfTestDetached { Set(availableFontURLs().map { $0.standardizedFileURL.path }) }
            try checkActive()
            let missing = document.materials.map { URL(fileURLWithPath: $0.face.path).standardizedFileURL.path }.filter
            { !paths.contains($0) }
            guard missing.isEmpty else {
                throw SelfTestFailure(
                    "recipe fonts are not available", detail: ["missing": missing.joined(separator: ", ")])
            }
            return ["files": String(document.materials.count)]
        case .scan:
            guard let engine, let document else { throw SelfTestFailure("engine or recipe missing") }
            var faces: [FaceRecord] = [], finished = false
            let stream = try await selfTestDetached { engine.scan(files: document.materials.map(\.face.path)) }
            for try await event in stream {
                try checkActive()
                switch event {
                case .face(let face): faces.append(face)
                case .fileError(let error): throw SelfTestFailure("\(error.path): \(error.message)")
                case .finished: finished = true
                case .progress: break
                }
            }
            try checkActive()
            guard finished else { throw SelfTestFailure("scan stopped without a result") }
            let loaded = document.makeRecipe(catalog: FaceCatalog(faces))
            guard loaded.report.isClean, loaded.report.outcomes.allSatisfy({ $0 == .byPath }) else {
                throw SelfTestFailure("recipe materials did not resolve cleanly by path")
            }
            recipe = loaded.recipe
            return ["faces": String(faces.count)]
        case .forge:
            guard let recipe, let engine, recipe.analyze().canForge else {
                throw SelfTestFailure("recipe cannot be built")
            }
            let path = root.appendingPathComponent("out/self-test.ttf").path
            let stream = try await selfTestDetached { engine.forge(recipe.forgeRequest(outputPath: path)) }
            for try await event in stream {
                try checkActive()
                if case .finished(let report) = event { self.report = report }
            }
            try checkActive()
            let exists = try await selfTestDetached { FileManager.default.fileExists(atPath: path) }
            try checkActive()
            guard let report, report.totalCodepoints > 0, exists else {
                throw SelfTestFailure("forge did not produce a nonempty font")
            }
            return ["characters": String(report.totalCodepoints), "postscript_name": report.postscriptName]
        case .verify:
            guard let report, let recipe else { throw SelfTestFailure("forge report missing") }
            let checkBuiltFont = dependencies.checkBuiltFont
            let check = try await selfTestDetached {
                try checkBuiltFont(
                    root.appendingPathComponent("out/self-test.ttf"), report.postscriptName, recipe.sampleText)
            }
            try checkActive()
            guard check.postScriptName == report.postscriptName, check.hasForgedMarker else {
                throw SelfTestFailure("built font checks failed")
            }
            return ["mapped_characters": String(check.mappedCharacters), "postscript_name": check.postScriptName]
        case .cancel:
            guard let recipe, let engine else { throw SelfTestFailure("engine or recipe missing") }
            return try await cancellationCheck(
                engine: engine,
                request: recipe.forgeRequest(outputPath: root.appendingPathComponent("out/cancel.ttf").path))
        case .cleanup:
            throw SelfTestFailure("cleanup is finalized separately")
        }
    }

    private func cancellationCheck(engine: any EngineRunning, request: ForgeRequest) async throws -> [String: String] {
        let helperProcessIDs = dependencies.helperProcessIDs
        let before = try await selfTestDetached { helperProcessIDs() }
        try checkActive()
        let probe = SelfTestCancelProbe()
        let worker = Task.detached {
            defer { probe.finish() }
            for try await event in engine.forge(request) {
                if case .progress = event { probe.progress() }
                try Task.checkCancellation()
            }
        }
        return try await withTaskCancellationHandler {
            do {
                while !probe.hasProgress {
                    guard !probe.finished else { throw SelfTestFailure("cancel forge stopped before progress") }
                    try await Task.sleep(for: .milliseconds(10))
                }
                let deadline = ContinuousClock.now.advanced(by: .seconds(1))
                var during = try await selfTestDetached { helperProcessIDs().subtracting(before) }
                while during.isEmpty && ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(50))
                    during = try await selfTestDetached { helperProcessIDs().subtracting(before) }
                }
                worker.cancel()
                let cancelled = ContinuousClock.now
                guard !during.isEmpty else { throw SelfTestFailure("no helper child process was seen") }
                let observed = during
                while try await selfTestDetached({ !helperProcessIDs().intersection(observed).isEmpty }) {
                    guard cancelled.duration(to: .now) < .seconds(3) else {
                        throw SelfTestFailure("helper is still alive 3 s after cancellation")
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                _ = await worker.result
                let exists = try await selfTestDetached { FileManager.default.fileExists(atPath: request.outputPath) }
                try checkActive()
                guard !exists else {
                    throw SelfTestFailure("cancelled forge left its output file")
                }
                return [
                    "pids": during.sorted().map(String.init).joined(separator: ","),
                    "ended_after_ms": String(selfTestMilliseconds(cancelled.duration(to: .now))),
                ]
            } catch {
                worker.cancel()
                _ = await worker.result
                throw error
            }
        } onCancel: {
            worker.cancel()
        }
    }

    func summary(exitCode: Int32, milliseconds: Int) -> SelfTestSummary {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return SelfTestSummary(
            result: exitCode == 0 ? "passed" : (exitCode == 4 ? "timed_out" : "failed"), failedSteps: failed,
            durationMs: milliseconds, appVersion: info.shortVersion, build: info.build,
            engine: kind?.rawValue ?? "none",
            fpengineVersion: engineVersion,
            macos: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
    }
}

private final class SelfTestCancelProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = false, ended = false
    func progress() { lock.withLock { seen = true } }
    func finish() { lock.withLock { ended = true } }
    var hasProgress: Bool { lock.withLock { seen } }
    var finished: Bool { lock.withLock { ended } }
}
