import FPCore
import Foundation
import Testing

@testable import FPEngineClient

@Suite(.serialized)
struct ProcessTests {
    @Test func helloFromFakeHelper() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let data = try #require(try RepoPaths.example("hello").split(separator: 10).first)
        let expected = try JSONDecoder().decode(EngineHello.self, from: Data(data))
        for scenario in ["hello_ok", "unknown_type"] {
            let client = EngineClient(configuration: area.configuration(scenario))
            let hello = try await client.hello()
            #expect(hello == expected)
            #expect(client.skippedUnknownEventCount == (scenario == "unknown_type" ? 1 : 0))
        }
        await #expect(throws: EngineError.incompatibleHelper(reported: 2, supported: 1)) {
            try await EngineClient(configuration: area.configuration("hello_v2")).hello()
        }
    }

    @Test func scanStreamsEventsInOrder() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let values = try await collect(
            EngineClient(configuration: area.configuration("scan_ok")).scan(files: ["/a", "/b"]))
        #expect(values.count == 8)
        let names = values.map { value in
            switch value {
            case .progress: "progress"
            case .face: "face"
            case .fileError: "fileError"
            case .finished: "finished"
            }
        }
        #expect(names == ["progress", "face", "face", "face", "fileError", "fileError", "progress", "finished"])
    }

    @Test func writesRequestArgumentsAndEnvironment() async throws {
        let area = try TestArea()
        defer { area.remove() }
        #expect(!FileManager.default.fileExists(atPath: area.temporary.path))
        _ = try await collect(
            EngineClient(configuration: area.configuration("scan_ok")).scan(files: ["/first", "/second"]))
        let lines = area.recorded().split(separator: "\n").map(String.init)
        #expect(lines.count == 6 && lines[0] == "argv:hello" && lines[3] == "argv:scan")
        #expect(lines[1] == "tmpdir:\(area.temporary.path)" && lines[4] == lines[1])
        #expect(!lines[5].contains("\\/"))
        let request = try JSONDecoder().decode([String: [String]].self, from: Data(lines[5].dropFirst(6).utf8))
        #expect(request == ["files": ["/first", "/second"]])
        #expect(FileManager.default.fileExists(atPath: area.temporary.path))
    }

    @Test func forgeFinishesOrThrowsHelperFailure() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let events = try await collect(
            EngineClient(configuration: area.configuration("forge_ok")).forge(area.request()))
        let line = try #require(try RepoPaths.example("forge-ok").split(separator: 10).last)
        let expected = try EventDecoder().decode(Data(line), command: "forge")
        guard case .result(_, _, let report?) = expected else { Issue.record("Expected report"); return }
        #expect(events.last == .finished(report))
        do {
            _ = try await collect(EngineClient(configuration: area.configuration("forge_error")).forge(area.request()))
            Issue.record("Expected helper failure")
        } catch EngineError.helperFailed(let error) {
            #expect(error.code == .staleMaterial && error.stage == .validate && error.materialIndex == 1)
        }
    }

    @Test func decodesSplitAndLargeLines() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let split = try await collect(EngineClient(configuration: area.configuration("split")).scan(files: []))
        #expect(split.count == 4)
        let big = try await collect(EngineClient(configuration: area.configuration("big_line")).scan(files: []))
        #expect(big.count == 2)
        guard case .face(let face) = big[0] else { Issue.record("Expected large face"); return }
        #expect(face.localNames[0].utf8.count == 2 * 1024 * 1024)
    }

    @Test("NATIVE-7: cancel sends SIGTERM and waits for exit") func native7CancelSendsSigterm() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let progress = Locked(false), observations = Locked<[EngineProcessEvent]>([])
        var configuration = area.configuration("slow")
        configuration.processObserver = { event in observations.update { $0.append(event) } }
        let client = EngineClient(configuration: configuration)
        let task = Task {
            for try await event in client.scan(files: []) {
                if case .progress = event { progress.update { $0 = true } }
            }
        }
        try await eventually { progress.read() }
        let start = ContinuousClock.now
        task.cancel()
        try await task.value
        #expect(start.duration(to: .now) < .milliseconds(500))
        #expect(area.recorded().contains("TERM"))
        guard case .exited(let pid, let code, let signal) = observations.read().last else {
            Issue.record("Expected exit observation"); return
        }
        #expect(code == 143 && signal == nil && !Signals.isAlive(pid))
    }

    @Test("NATIVE-7: SIGKILL escalation removes helper leftovers") func native7EscalatesToSigkillAndCleansLeftovers()
        async throws
    {
        let area = try TestArea()
        defer { area.remove() }
        let progress = Locked(false)
        let client = EngineClient(configuration: area.configuration("ignore_term"))
        let task = Task {
            for try await event in client.forge(area.request()) {
                if case .progress = event { progress.update { $0 = true } }
            }
        }
        try await eventually { progress.read() }
        let start = ContinuousClock.now
        task.cancel()
        try await task.value
        let elapsed = start.duration(to: .now)
        #expect(elapsed >= .milliseconds(1800) && elapsed < .milliseconds(3500))
        #expect(try FileManager.default.contentsOfDirectory(atPath: area.temporary.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: area.output.path).isEmpty)
    }

    @Test func timeoutsTerminateTheHelper() async throws {
        let area = try TestArea()
        defer { area.remove() }
        var configuration = area.configuration("slow")
        configuration.timeouts.forge = .milliseconds(500)
        configuration.timeouts.scanIdle = .milliseconds(500)
        let client = EngineClient(configuration: configuration)
        for command in ["scan", "forge"] {
            let start = ContinuousClock.now
            do {
                if command == "scan" {
                    _ = try await collect(client.scan(files: []))
                } else {
                    _ = try await collect(client.forge(area.request()))
                }
                Issue.record("Expected timeout")
            } catch EngineError.timedOut(let duration, _) {
                #expect(duration == .milliseconds(500))
                #expect(start.duration(to: .now) < .milliseconds(3500))
            }
        }
    }

    @Test func classifiesAbnormalEnds() async throws {
        let area = try TestArea()
        defer { area.remove() }
        for scenario in ["crash", "no_terminal", "early_exit", "garbage", "truncated", "interrupted"] {
            let client = EngineClient(configuration: area.configuration(scenario))
            let files =
                scenario == "early_exit"
                ? Array(repeating: "/" + String(repeating: "a", count: 209), count: 40_000) : []
            do {
                _ = try await collect(client.scan(files: files))
                Issue.record("Expected error for \(scenario)")
            } catch let error as EngineError {
                switch (scenario, error) {
                case ("crash", .crashed(let code, let signal, let tail)):
                    #expect(code == nil && signal == 11 && tail.contains("fake: about to crash"))
                case ("early_exit", .crashed(let code, let signal, _)): #expect(code == 3 && signal == nil)
                case ("no_terminal", .protocolViolation), ("garbage", .protocolViolation),
                    ("truncated", .protocolViolation):
                    break
                case ("interrupted", .interrupted(let code, _, _)): #expect(code == 143)
                default: Issue.record("Unexpected \(error) for \(scenario)")
                }
            }
        }
    }

    @Test func drainsStderrFlood() async throws {
        let area = try TestArea()
        defer { area.remove() }
        for (scenario, bytes) in [("stderr_flood", 1_048_576), ("stderr_flood_large", 4_194_304)] {
            let logs = Locked<[String]>([])
            var configuration = area.configuration(scenario)
            configuration.logHandler = { line in logs.update { $0.append(line) } }
            let client = EngineClient(configuration: configuration)
            let start = ContinuousClock.now
            _ = try await client.hello()
            #expect(start.duration(to: .now) < .seconds(5))
            #expect(logs.read().reduce(0) { $0 + $1.utf8.count } == bytes)
            #expect(logs.read().allSatisfy { $0.utf8.count <= 65_536 })
            #expect(client.lastStderrByteCount == configuration.stderrCapacity)
        }
    }

    @Test func helloGateRunsOnceAndBlocksIncompatibleHelpers() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let client = EngineClient(configuration: area.configuration("scan_ok"))
        async let left = collect(client.scan(files: []))
        async let right = collect(client.scan(files: []))
        _ = try await (left, right)
        #expect(area.recorded().components(separatedBy: "argv:hello").count == 2)
        try FileManager.default.removeItem(at: area.record)
        let incompatible = EngineClient(configuration: area.configuration("hello_v2"))
        for _ in 0..<2 {
            await #expect(throws: EngineError.incompatibleHelper(reported: 2, supported: 1)) {
                try await collect(incompatible.scan(files: []))
            }
        }
        #expect(area.recorded().components(separatedBy: "argv:hello").count == 2)
        #expect(!area.recorded().contains("argv:scan"))
    }

    @Test func processObserverReportsLaunchAndExit() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let seen = Locked<[EngineProcessEvent]>([]), progress = Locked(false)
        var configuration = area.configuration("slow")
        configuration.processObserver = { event in seen.update { $0.append(event) } }
        let client = EngineClient(configuration: configuration)
        let task = Task {
            for try await event in client.scan(files: []) {
                if case .progress = event { progress.update { $0 = true } }
            }
        }
        try await eventually { progress.read() }
        task.cancel()
        try await task.value
        let events = seen.read()
        #expect(events.count == 4)
        guard case .launched(let helloPID, "hello") = events[0],
            case .exited(helloPID, 0, nil) = events[1], case .launched(let scanPID, "scan") = events[2]
        else { Issue.record("Unexpected observer sequence"); return }
        #expect(events[3] == .exited(pid: scanPID, exitCode: 143, signal: nil))
        #expect(!Signals.isAlive(scanPID))
    }

    @Test func directHelloAndPermanentGateFailuresAreCached() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let client = EngineClient(configuration: area.configuration("scan_ok"))
        _ = try await client.hello()
        _ = try await collect(client.scan(files: []))
        #expect(area.recorded().components(separatedBy: "argv:hello").count == 2)
        try FileManager.default.removeItem(at: area.record)
        let missing = EngineClient(configuration: area.configuration("hello_missing_capability"))
        for _ in 0..<2 {
            await #expect(throws: EngineError.protocolViolation("helper lacks capability 'scan'", stderrTail: "")) {
                try await collect(missing.scan(files: []))
            }
        }
        #expect(area.recorded().components(separatedBy: "argv:hello").count == 2)
        #expect(!area.recorded().contains("argv:scan"))
    }

    @Test func decodingGateFailuresAreRetried() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let client = EngineClient(configuration: area.configuration("hello_garbage"))
        for _ in 0..<2 {
            await #expect(throws: EngineError.self) { try await collect(client.scan(files: [])) }
        }
        #expect(area.recorded().components(separatedBy: "argv:hello").count == 3)
        #expect(!area.recorded().contains("argv:scan"))
    }

    @Test func helloCancellationAndTimeoutStopTheHelper() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let observations = Locked<[EngineProcessEvent]>([])
        var configuration = area.configuration("hello_slow")
        configuration.processObserver = { event in observations.update { $0.append(event) } }
        let client = EngineClient(configuration: configuration)
        let task = Task { try await client.hello() }
        try await eventually { area.recorded().contains("argv:hello") }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        guard case .exited(let pid, _, _) = observations.read().last else {
            Issue.record("Expected cancelled hello to exit"); return
        }
        #expect(!Signals.isAlive(pid))
        configuration.timeouts.hello = .milliseconds(100)
        do {
            _ = try await EngineClient(configuration: configuration).hello()
            Issue.record("Expected hello timeout")
        } catch EngineError.timedOut(let duration, _) { #expect(duration == .milliseconds(100)) }
    }

    @Test func terminalResultWinsOverExitAndLaterOutput() async throws {
        let area = try TestArea()
        defer { area.remove() }
        for scenario in ["result_linger", "result_nonzero"] {
            let logs = Locked<[String]>([])
            var configuration = area.configuration(scenario)
            configuration.timeouts.terminationGrace = .milliseconds(100)
            configuration.logHandler = { line in logs.update { $0.append(line) } }
            let values = try await collect(EngineClient(configuration: configuration).scan(files: []))
            #expect(values.count == 8)
            guard case .finished = values.last else { Issue.record("Expected terminal result"); return }
            #expect(logs.read().contains { $0.contains("terminal event takes precedence") })
        }
    }

    @Test func scanIdleResetsForUnknownLines() async throws {
        let area = try TestArea()
        defer { area.remove() }
        var configuration = area.configuration("idle_reset")
        configuration.timeouts.scanIdle = .milliseconds(400)
        let start = ContinuousClock.now
        let client = EngineClient(configuration: configuration)
        let values = try await collect(client.scan(files: []))
        #expect(start.duration(to: .now) > .milliseconds(500))
        #expect(values.count == 8)
        #expect(client.skippedUnknownEventCount == 4)
    }

    @Test func inheritedPipeDoesNotPreventCompletion() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let start = ContinuousClock.now
        do {
            _ = try await collect(EngineClient(configuration: area.configuration("inherited_pipe")).scan(files: []))
            Issue.record("Expected truncated line")
        } catch EngineError.protocolViolation(let message, _) { #expect(message == "truncated line") }
        #expect(start.duration(to: .now) < .milliseconds(1800))
    }

    @Test func droppingIteratorCancelsTheRun() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let observations = Locked<[EngineProcessEvent]>([])
        var configuration = area.configuration("slow")
        configuration.processObserver = { event in observations.update { $0.append(event) } }
        let client = EngineClient(configuration: configuration)
        for try await _ in client.scan(files: []) { break }
        try await eventually { observations.read().count == 4 }
        guard case .exited(let pid, _, _) = observations.read().last else {
            Issue.record("Expected exit after iterator disposal"); return
        }
        #expect(!Signals.isAlive(pid))
    }

    @Test func cancellingOneGateWaiterKeepsOtherWaitersAlive() async throws {
        let area = try TestArea()
        defer { area.remove() }
        let observations = Locked<[EngineProcessEvent]>([])
        var configuration = area.configuration("hello_slow")
        configuration.processObserver = { event in observations.update { $0.append(event) } }
        let client = EngineClient(configuration: configuration)
        let first = Task { try await collect(client.scan(files: [])) }
        let second = Task { try await collect(client.scan(files: [])) }
        try await eventually { area.recorded().contains("argv:hello") }
        try await Task.sleep(for: .milliseconds(50))
        first.cancel()
        _ = try await first.value
        try await Task.sleep(for: .milliseconds(50))
        #expect(observations.read().count == 1)
        second.cancel()
        _ = try await second.value
        try await eventually { observations.read().count == 2 }
        guard case .exited(let pid, _, _) = observations.read().last else {
            Issue.record("Expected gate hello to exit when all waiters cancel"); return
        }
        #expect(!Signals.isAlive(pid))
        #expect(!area.recorded().contains("argv:scan"))
        #expect(area.recorded().components(separatedBy: "argv:hello").count == 2)
    }
}
