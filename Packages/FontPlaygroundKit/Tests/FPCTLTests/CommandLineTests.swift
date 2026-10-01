import Foundation
import Testing

@testable import fpctl

struct CommandLineTests {
    @Test func parsesCommandLines() throws {
        let failures: [([String], UsageError)] = [
            ([], .missingCommand), (["frob"], .unknownCommand("frob")),
            (["forge", "r.fontrecipe"], .missingArgument("--out")),
            (["forge", "r.fontrecipe", "--out"], .missingValue("--out")),
            (["scan"], .missingArgument("a font file or folder")),
            (["hello", "--font-dir", "x"], .optionNotAllowed(option: "--font-dir", command: "hello")),
            (["hello", "--wat"], .unknownOption("--wat")),
            (["hello", "a"], .unexpectedArgument("/tmp/a")),
            (["forge", "r", "s", "--out=x"], .unexpectedArgument("/tmp/s")),
            (["scan", "a", "--quiet"], .optionNotAllowed(option: "--quiet", command: "scan")),
            (["scan", "--json=true", "a"], .unknownOption("--json=true")),
            (["--engine=", "hello"], .missingValue("--engine")),
        ]
        for (arguments, expected) in failures {
            #expect(throws: expected) { try FPCTL.parse(arguments, currentDirectory: "/tmp") }
        }
        #expect(
            try FPCTL.parse(["--engine=/p", "scan", "a.ttf", "--json"], currentDirectory: "/tmp")
                == Invocation(enginePath: "/p", verbose: false, command: .scan(paths: ["/tmp/a.ttf"], json: true)))
        #expect(
            try FPCTL.parse(
                ["forge", "--out=o.ttf", "r.fontrecipe", "--font-dir", "d1", "--font-dir", "d2"],
                currentDirectory: "/tmp")
                == Invocation(
                    enginePath: nil, verbose: false,
                    command: .forge(
                        recipe: "/tmp/r.fontrecipe", out: "/tmp/o.ttf", fontDirectories: ["/tmp/d1", "/tmp/d2"],
                        allowMissing: false, json: false, quiet: false)))
        #expect(
            try FPCTL.parse(["scan", "--", "--weird.ttf"], currentDirectory: "/tmp").command
                == .scan(paths: ["/tmp/--weird.ttf"], json: false))
        #expect(try FPCTL.parse(["hello", "-h"], currentDirectory: "/tmp").command == .help)
        #expect(
            try FPCTL.parse(["--verbose", "scan", "../font.TTF"], currentDirectory: "/tmp/sub").command
                == .scan(paths: ["/tmp/font.TTF"], json: false))
    }
    @Test func usageErrorsAndHelp() async throws {
        for arguments in [[], ["frob"], ["--unknown"], ["scan"], ["hello", "x"], ["hello", "--out=x"], ["--engine"]] {
            let capture = CapturedOutput()
            let code = await FPCTL.run(
                arguments, environment: [:], currentDirectory: "/tmp", output: capture.output,
                makeEngine: { _, _, _ in
                    Issue.record("Engine must not be constructed"); throw CommandStopped()
                })
            #expect(code == 2)
            #expect(capture.err.hasSuffix("Run 'fpctl --help' for usage."))
            #expect(capture.out.isEmpty)
        }
        for arguments in [["--help"], ["hello", "-h"], ["--version"]] {
            let capture = CapturedOutput()
            let code = await FPCTL.run(
                arguments, environment: [:], currentDirectory: "/tmp", output: capture.output,
                makeEngine: { _, _, _ in
                    Issue.record("Engine must not be constructed"); throw CommandStopped()
                })
            #expect(code == 0)
            #expect(capture.out == (arguments == ["--version"] ? "fpctl 1.0.0" : FPCTL.usage))
            #expect(capture.err.isEmpty)
        }
        let spec = try String(contentsOf: cliRepo.appendingPathComponent("docs/specs/helper.md"), encoding: .utf8)
        #expect(spec.contains("```\n" + FPCTL.usage + "\n```"))
    }
    @Test func foldersSortAndFilterWithoutDroppingExplicitErrors() throws {
        let area = try CLIArea(); defer { area.remove() }
        for name in ["a.ttf", "Z.OTF", "sub/b.ttc", "__MACOSX/c.ttf", ".Trashes/d.ttf", "._e.ttf", "notes.txt"] {
            let file = area.file(name)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        let missing = area.file("absent.ttf").path
        #expect(
            FontFolders.files(in: [area.root.path, missing, area.file("a.ttf").path]).files == [
                "Z.OTF", "a.ttf", "sub/b.ttc",
            ].map { area.file($0).path } + [missing, area.file("a.ttf").path])
    }
    @Test func explicitlyNamedPathsAreNeverFilteredOut() throws {
        let area = try CLIArea(); defer { area.remove() }
        for name in ["__MACOSX/c.ttf", "__MACOSX/._f.ttf", "._e.ttf"] {
            let file = area.file(name)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        // A named file goes to the helper, which reports it; a named folder is walked with the usual filter.
        #expect(
            FontFolders.files(in: [area.file("._e.ttf").path, area.file("__MACOSX").path]).files == [
                area.file("._e.ttf").path, area.file("__MACOSX/c.ttf").path,
            ])
    }
}
