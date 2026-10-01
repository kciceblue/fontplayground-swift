import FPCore
import FPEngineClient
import Foundation
import Testing

@testable import fpctl

@Suite(.serialized) struct CLIFlows {
    @Test func forgeFlowsWithFakeEngine() async throws {
        let area = try CLIArea(); defer { area.remove() }
        let available = FaceRecord(
            path: area.file("a.ttf").path, family: "Available", coverage: .init(scalarsOf: "abc"),
            postscriptName: "Available-Regular")
        let absent = FaceRecord(
            path: area.file("absent.ttf").path, family: "Fixture Missing", coverage: .init(scalarsOf: "漢"),
            postscriptName: "FixtureMissing-Regular")
        try Data().write(to: area.file("a.ttf"))
        let recipe = try area.recipe([available, absent])
        let folder = area.file("empty")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let args = ["forge", recipe, "--font-dir", folder.path, "--out", area.file("out.ttf").path]
        let engine = FakeCLIEngine(faces: [available]), capture = CapturedOutput()
        #expect(
            await FPCTL.run(
                args, environment: [:], currentDirectory: area.root.path, output: capture.output,
                makeEngine: { _, _, _ in engine.handle }) == 4)
        #expect(capture.err.contains("Fixture Missing Regular (PostScript FixtureMissing-Regular)"))
        #expect(engine.forges.isEmpty)
        #expect(engine.scans.count == 2)
        let allowed = CapturedOutput()
        #expect(
            await FPCTL.run(
                args + ["--allow-missing", "--json"], environment: [:], currentDirectory: area.root.path,
                output: allowed.output, makeEngine: { _, _, _ in engine.handle }) == 0)
        #expect(engine.forges.count == 1)
        #expect(engine.forges[0].spec.materials.count == 1)
        #expect(allowed.err.contains("fpctl: warning: building without:"))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(allowed.out.utf8)) as? [String: Any])
        let unresolved = try #require(json["unresolved"] as? [[String: String]])
        #expect(
            unresolved == [
                ["postscript_name": "FixtureMissing-Regular", "family": "Fixture Missing", "style": "Regular"]
            ])
        #expect(allowed.err.components(separatedBy: "Preparing Available Regular…").count == 2)
        for mode in [FakeCLIEngine.Mode.fail, .noResult] {
            let failing = FakeCLIEngine(faces: [available], mode: mode), output = CapturedOutput()
            let code = await FPCTL.run(
                args + ["--allow-missing", "--verbose", "--quiet"], environment: [:], currentDirectory: area.root.path,
                output: output.output, makeEngine: { _, _, _ in failing.handle })
            #expect(code == (mode == .fail ? 1 : 3))
            #expect(!output.err.contains("Preparing"))
            if mode == .fail {
                #expect(output.err.contains("fpctl: forge failed (unsupported_font, validate): cannot use this font"))
                #expect(output.err.contains("verbose details"))
            } else {
                #expect(output.err.contains("font engine stopped without a result"))
            }
        }
        let unavailable = CapturedOutput()
        #expect(
            await FPCTL.run(
                args, environment: [:], currentDirectory: area.root.path, output: unavailable.output,
                makeEngine: { _, _, _ in throw EngineError.helperNotFound(searched: []) }) == 3)
        #expect(unavailable.err == "fpctl: can't find the font engine; set FP_ENGINE_PYTHON or pass --engine")
        let waiting = FakeCLIEngine(faces: [available], mode: .wait)
        let task = Task {
            await FPCTL.run(
                args + ["--allow-missing"], environment: [:], currentDirectory: area.root.path,
                output: CapturedOutput().output, makeEngine: { _, _, _ in waiting.handle })
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while waiting.forges.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!waiting.forges.isEmpty)
        let started = ContinuousClock.now
        FPCTL.interrupt()
        #expect(await task.value == 130)
        #expect(started.duration(to: .now) < .seconds(1))
    }
    @Test func discardedRecipeEntriesAreReported() async throws {
        let area = try CLIArea(); defer { area.remove() }
        let face = FaceRecord(
            path: area.file("a.ttf").path, family: "A", coverage: .init(scalarsOf: "abc"), postscriptName: "A-Regular")
        let path = try area.recipe([face]), engine = FakeCLIEngine(faces: [face]), output = CapturedOutput()
        var document = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let rows = try #require(document["materials"] as? [[String: Any]])
        document["materials"] = rows + rows
        document["main"] = 9
        document["rules"] = ["klingon": 0, "han": 9]
        try AtomicFile.write(JSONSerialization.data(withJSONObject: document), to: path)
        #expect(
            await FPCTL.run(
                ["forge", path, "--font-dir", area.root.path, "--out", area.file("out.ttf").path], environment: [:],
                currentDirectory: area.root.path, output: output.output, makeEngine: { _, _, _ in engine.handle }) == 0)
        #expect(output.err.contains("ignored recipe rule: klingon=0"))
        #expect(output.err.contains("ignored recipe rule: han=9"))
        #expect(output.err.contains("main font is out of range"))
        #expect(output.err.contains("material 2 duplicates material 1"))
        #expect(engine.forges[0].spec.materials.count == 1)
    }

    @Test func malformedRecipeIsAnInputError() async throws {
        let area = try CLIArea(); defer { area.remove() }
        let engine = FakeCLIEngine()
        for (name, bytes) in [
            ("bad.fontrecipe", "{"), ("future.fontrecipe", "{\"format\":\"fontrecipe\",\"version\":2}"),
        ] {
            try Data(bytes.utf8).write(to: area.file(name))
            let output = CapturedOutput()
            #expect(
                await FPCTL.run(
                    ["forge", area.file(name).path, "--out", area.file("out.ttf").path], environment: [:],
                    currentDirectory: area.root.path, output: output.output,
                    makeEngine: { _, _, _ in
                        Issue.record("Input validation must precede engine launch"); return engine.handle
                    })
                    == 2)
            #expect(output.err.contains("not a valid Font Playground recipe"))
        }
        let output = CapturedOutput()
        #expect(
            await FPCTL.run(
                ["forge", area.file("absent.fontrecipe").path, "--out", area.file("out.ttf").path], environment: [:],
                currentDirectory: area.root.path, output: output.output,
                makeEngine: { _, _, _ in
                    Issue.record("Input validation must precede engine launch"); return engine.handle
                }) == 2)
        #expect(engine.scans.isEmpty && engine.forges.isEmpty)
    }
}
