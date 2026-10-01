import FPCore
import FPEngineClient
import Foundation
import Testing

@testable import fpctl

extension CLIFlows {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"] != nil))
    func helloPrintsEngineVersion() async throws {
        for json in [false, true] {
            let output = CapturedOutput()
            #expect(
                await FPCTL.run(
                    ["hello"] + (json ? ["--json"] : []), environment: ProcessInfo.processInfo.environment,
                    currentDirectory: cliRepo.path, output: output.output) == 0)
            if json {
                #expect(try JSONDecoder().decode(EngineHello.self, from: Data(output.out.utf8)).protocolVersion == 1)
            } else {
                #expect(output.out.hasPrefix("fpengine ")); #expect(output.out.contains("helper: "))
            }
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"] != nil))
    func scanListsFixtureFaces() async throws {
        let area = try CLIArea(); defer { area.remove() }
        let fonts = try area.fonts()
        for json in [false, true] {
            let output = CapturedOutput()
            #expect(
                await FPCTL.run(
                    ["scan", fonts.path] + (json ? ["--json"] : []), environment: ProcessInfo.processInfo.environment,
                    currentDirectory: cliRepo.path, output: output.output) == 0)
            #expect(output.err.contains("NotAFont.ttf")); #expect(output.err.contains("(unreadable)"))
            if json {
                let result = try JSONDecoder().decode(ScanPayload.self, from: Data(output.out.utf8))
                #expect(result.faces.count == 9 && result.errors.count == 1 && result.summary.files == 9)
            } else {
                #expect(output.out.split(separator: "\n").count == 9)
            }
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"] != nil))
    func forgeFixtureRecipeEndToEnd() async throws {
        let area = try CLIArea(); defer { area.remove() }
        let fonts = try area.fonts(), output = CapturedOutput()
        let path = area.file("out.ttf").path
        #expect(
            await FPCTL.run(
                ["forge", "examples/fixtures/latin-cjk.fontrecipe", "--font-dir", fonts.path, "--out", path, "--json"],
                environment: ProcessInfo.processInfo.environment,
                currentDirectory: cliRepo.path, output: output.output) == 0)
        struct Payload: Decodable { let report: ForgeReport; let unresolved: [PortableFaceIdentity] }
        let report = try JSONDecoder().decode(Payload.self, from: Data(output.out.utf8))
        #expect(report.report.totalCodepoints == 3650 && report.report.materials.map(\.codepoints) == [240, 3410])
        #expect(report.unresolved.isEmpty)
        #expect(FileManager.default.fileExists(atPath: path))
        let scan = CapturedOutput()
        #expect(
            await FPCTL.run(
                ["scan", path, "--json"], environment: ProcessInfo.processInfo.environment,
                currentDirectory: cliRepo.path, output: scan.output) == 0)
        let result = try JSONDecoder().decode(ScanPayload.self, from: Data(scan.out.utf8))
        #expect(result.faces.count == 1)
        let face = try #require(result.faces.first)
        #expect(face.family == "Fixture Sans CJK" && face.isForged && face.coverage.count == 3650)
        #expect(output.err.contains("[ 70%] Combining the fonts…"))
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"] != nil))
    func engineErrorExits1() async throws {
        let area = try CLIArea(); defer { area.remove() }
        let fonts = try area.fonts()
        let face = FaceRecord(
            path: fonts.appendingPathComponent("FixtureColor-Regular.ttf").path, family: "Fixture Color",
            coverage: .empty, postscriptName: "FixtureColor-Regular")
        let path = try area.recipe([face]), output = CapturedOutput()
        #expect(
            await FPCTL.run(
                ["forge", path, "--font-dir", area.root.path, "--out", area.file("out.ttf").path],
                environment: ProcessInfo.processInfo.environment, currentDirectory: cliRepo.path, output: output.output)
                == 1)
        #expect(output.err.contains("fpctl: forge failed (unsupported_font, validate):"))
    }
    @Test func exampleRecipesDecode() throws {
        let documents = try ["examples/latin-cjk.fontrecipe", "examples/fixtures/latin-cjk.fontrecipe"].map {
            try RecipeDocument.decode(Data(contentsOf: cliRepo.appendingPathComponent($0)))
        }
        let identities = documents[0].materials.map(\.face)
        #expect(identities[0].postscriptName == "HelveticaNeue")
        #expect(identities[0].path == "/System/Library/Fonts/HelveticaNeue.ttc" && identities[0].index == 0)
        #expect(identities[1].postscriptName == "PingFangSC-Regular" && identities[1].index == 3)
        #expect(documents[1].materials.map(\.face.postscriptName) == ["FixtureSans-Regular", "FixtureCJK-Regular"])
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"] != nil))
    func fixtureRecipeResolvesByPostScriptName() async throws {
        let area = try CLIArea(); defer { area.remove() }
        let fonts = try area.fonts(), output = CapturedOutput()
        #expect(
            await FPCTL.run(
                ["scan", fonts.path, "--json"], environment: ProcessInfo.processInfo.environment,
                currentDirectory: cliRepo.path, output: output.output) == 0)
        let result = try JSONDecoder().decode(ScanPayload.self, from: Data(output.out.utf8))
        let document = try RecipeDocument.decode(
            Data(contentsOf: cliRepo.appendingPathComponent("examples/fixtures/latin-cjk.fontrecipe")))
        let loaded = document.makeRecipe(catalog: FaceCatalog(result.faces))
        #expect(loaded.report.outcomes == [.byPostScriptName, .byPostScriptName] && loaded.report.unresolved.isEmpty)
    }
}
private struct ScanPayload: Decodable {
    let faces: [FaceRecord]
    let errors: [ScanFileError]
    let summary: ScanSummary
    enum CodingKeys: String, CodingKey { case faces, errors = "file_errors", summary }
}
