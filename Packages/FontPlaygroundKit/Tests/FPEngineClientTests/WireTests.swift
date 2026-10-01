import FPCore
import Foundation
import Testing

@testable import FPEngineClient

struct WireTests {
    @Test func lineFramerHandlesEverySplitPoint() throws {
        let input = Data("one\ntwo\nthree\n".utf8)
        let expected = ["one", "two", "three"].map { Data($0.utf8) }
        for index in 0...input.count {
            var framer = LineFramer()
            let first = try framer.append(input.prefix(index))
            let last = try framer.append(input.dropFirst(index))
            #expect(first + last == expected)
            #expect(framer.finish() == nil)
        }
        var framer = LineFramer()
        var lines: [Data] = []
        for byte in input { lines += try framer.append([byte]) }
        #expect(lines == expected)
        #expect(try framer.append(Data("\n\npartial".utf8)).isEmpty)
        #expect(framer.finish() == Data("partial".utf8))
        #expect(throws: LineFramer.Error.self) {
            try framer.append(Data(repeating: 120, count: LineFramer.maximumLineBytes + 1))
        }
    }

    @Test func stderrRingKeepsTail() {
        var ring = StderrRing(capacity: 16)
        ring.append(Data("0123456789abcdefghij".utf8))
        #expect(ring.tail == "456789abcdefghij" && ring.byteCount == 16)
        ring.append([0xff])
        #expect(ring.tail == "56789abcdefghij�" && ring.byteCount == 16)
    }

    @Test func decodesProtocolExamples() throws {
        let decoder = EventDecoder()
        var cases: [String: Int] = [:]
        for (name, command) in [("hello", "hello"), ("scan", "scan"), ("forge-ok", "forge"), ("forge-error", "forge")] {
            let lines = try RepoPaths.example(name).split(separator: 10)
            for line in lines {
                let event = try #require(try decoder.decode(Data(line), command: command))
                switch event {
                case .hello: cases["hello", default: 0] += 1
                case .progress: cases["progress", default: 0] += 1
                case .face: cases["face", default: 0] += 1
                case .fileError: cases["file_error", default: 0] += 1
                case .result: cases["result", default: 0] += 1
                case .error: cases["error", default: 0] += 1
                }
            }
        }
        #expect(Set(cases.keys) == ["hello", "progress", "face", "file_error", "result", "error"])
        #expect(cases["face"] == 3 && cases["result"] == 3)
        #expect(throws: EngineError.incompatibleHelper(reported: 2, supported: 1)) {
            try decoder.decode(Data(#"{"protocol":2,"type":"hello"}"#.utf8), command: "hello")
        }
        #expect(throws: EngineError.self) { try decoder.decode(Data("not json".utf8), command: "hello") }
        #expect(try decoder.decode(Data(#"{"protocol":1,"type":"future"}"#.utf8), command: "hello") == nil)
        #expect(throws: EngineError.self) {
            try decoder.decode(Data(#"{"protocol":1,"type":"face","face":{}}"#.utf8), command: "forge")
        }
    }

    @Test func resolvesBundledHelperFirst() throws {
        let area = try TestArea()
        defer { area.remove() }
        let bundle = area.root.appendingPathComponent("Test.app")
        let first = bundle.appendingPathComponent(EngineLaunch.bundledHelperCandidates[0]).path
        let second = bundle.appendingPathComponent(EngineLaunch.bundledHelperCandidates[1]).path
        let python = area.root.appendingPathComponent("python").path
        for path in [first, second, python] { try fakeExecutable(at: path) }
        let environment = ["FP_ENGINE_PYTHON": python]
        let launch = try EngineLaunch.resolve(environment: environment, bundleURL: bundle)
        #expect(launch.executableURL.path == first && launch.source == .bundled)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: first)
        let fallback = try EngineLaunch.resolve(environment: environment, bundleURL: bundle)
        #expect(fallback.executableURL.path == second && fallback.source == .bundled)
    }

    @Test func fallsBackToFPEnginePython() throws {
        let area = try TestArea()
        defer { area.remove() }
        let python = area.root.appendingPathComponent("python").path
        try fakeExecutable(at: python)
        let value = try EngineLaunch.resolve(
            environment: ["FP_ENGINE_PYTHON": python], bundleURL: area.root.appendingPathComponent("Absent.app"))
        #expect(value.source == .environment && value.executableURL.path == python)
    }

    @Test func reportsHelperNotFound() throws {
        let area = try TestArea()
        defer { area.remove() }
        let bundle = area.root.appendingPathComponent("Test.app")
        let python = area.root.appendingPathComponent("python").path
        let paths =
            EngineLaunch.bundledHelperCandidates.map { bundle.appendingPathComponent($0).path } + [python]
        #expect(throws: EngineError.helperNotFound(searched: paths)) {
            try EngineLaunch.resolve(environment: ["FP_ENGINE_PYTHON": python], bundleURL: bundle)
        }
    }

    private func fakeExecutable(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
    }

    @Test func fakeHelperMatchesProtocolExamples() throws {
        let area = try TestArea()
        defer { area.remove() }
        for (scenario, command, example) in [
            ("hello_ok", "hello", "hello"), ("scan_ok", "scan", "scan"), ("forge_ok", "forge", "forge-ok"),
            ("forge_error", "forge", "forge-error"),
        ] {
            let launch = area.configuration(scenario).launch
            let process = Process(), output = Pipe(), input = Pipe()
            process.executableURL = launch.executableURL
            process.arguments = launch.arguments + [command]
            process.environment = ProcessInfo.processInfo.environment.merging(launch.environment) { _, new in new }
            process.standardInput = input
            process.standardOutput = output
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: Data("{}".utf8))
            try input.fileHandleForWriting.close()
            let bytes = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(bytes == (try RepoPaths.example(example)))
        }
    }
}
