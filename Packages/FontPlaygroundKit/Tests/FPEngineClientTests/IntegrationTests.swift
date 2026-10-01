import FPCore
import Foundation
import Testing

@testable import FPEngineClient

struct IntegrationTests {
    @Test func sweepRemovesOnlyDeadRuns() throws {
        let area = try TestArea()
        defer { area.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit 0"]
        try process.run()
        process.waitUntilExit()
        let dead = process.processIdentifier
        #expect(!Signals.isAlive(dead))
        let live = ProcessInfo.processInfo.processIdentifier
        try FileManager.default.createDirectory(at: area.temporary, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: area.output, withIntermediateDirectories: true)
        let old = area.temporary.appendingPathComponent("fpengine-\(live)-old")
        let keep = area.temporary.appendingPathComponent("fpengine-\(live)-c")
        for directory in [old, keep, area.temporary.appendingPathComponent("fpengine-\(dead)-a")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let partial = area.output.appendingPathComponent(".fpengine-\(dead)-b.partial.ttf")
        try Data("partial".utf8).write(to: partial)
        let unrelated = area.temporary.appendingPathComponent("unrelated.txt")
        try Data().write(to: unrelated)
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-86_401)], ofItemAtPath: old.path)
        let count = EngineClient.sweepLeftovers(
            temporaryDirectory: area.temporary, outputDirectories: [area.output], now: now)
        #expect(count == 3)
        #expect(FileManager.default.fileExists(atPath: keep.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"] != nil))
    func realHelperEndToEnd() async throws {
        let python = try #require(ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"])
        let area = try TestArea()
        defer { area.remove() }
        let fonts = area.root.appendingPathComponent("fonts")
        let generator = Process()
        generator.executableURL = URL(fileURLWithPath: python)
        generator.arguments = ["-I", "-B", "-m", "fpengine.testing.make_fonts", fonts.path]
        generator.standardOutput = FileHandle.nullDevice
        try generator.run()
        generator.waitUntilExit()
        #expect(generator.terminationStatus == 0)
        struct FontList: Decodable {
            struct Entry: Decodable { var file: String }
            var fonts: [Entry]
        }
        let manifest = try JSONDecoder().decode(
            FontList.self, from: Data(contentsOf: fonts.appendingPathComponent("fonts.json")))
        let configuration = EngineConfiguration(
            launch: .init(executableURL: URL(fileURLWithPath: python)), temporaryDirectory: area.temporary)
        let client = EngineClient(configuration: configuration)
        #expect(try await client.hello().protocolVersion == 1)
        let scanned = try await collect(
            client.scan(files: manifest.fonts.map { fonts.appendingPathComponent($0.file).path }))
        var faces: [FaceRecord] = [], errors: [ScanFileError] = []
        for event in scanned {
            switch event {
            case .face(let face): faces.append(face)
            case .fileError(let error): errors.append(error)
            default: break
            }
        }
        #expect(faces.count == 9 && errors.count == 1 && errors[0].code == .unreadable)
        guard case .finished(let summary) = scanned.last else { Issue.record("Expected scan summary"); return }
        #expect(summary.files == 9)
        let materials = try ["FixtureSans-Regular.ttf", "FixtureCJK-Regular.otf"].map { name in
            let face = try #require(faces.first { URL(fileURLWithPath: $0.path).lastPathComponent == name })
            return ForgeSpec.MaterialSpec(
                path: face.path, index: face.index,
                expect: .init(postscriptName: face.postscriptName, size: face.size, mtime: face.mtime)
            )
        }
        var request = ForgeRequest(
            spec: .init(
                materials: materials, scriptRules: [.han: 1, .kana: 1, .cjkSymbols: 1], familyName: "Fixture Client"),
            outputPath: area.request().outputPath
        )
        let forged = try await collect(client.forge(request))
        guard case .finished(let report) = forged.last else { Issue.record("Expected forge report"); return }
        #expect(report.totalCodepoints == 3650 && report.materials.map(\.codepoints) == [240, 3410])
        #expect(FileManager.default.fileExists(atPath: request.outputPath))
        request.spec.materials[1].expect?.size += 1
        do {
            _ = try await collect(client.forge(request))
            Issue.record("Expected stale material failure")
        } catch EngineError.helperFailed(let failure) {
            #expect(failure.code == .staleMaterial && failure.materialIndex == 1)
        }
    }
}
