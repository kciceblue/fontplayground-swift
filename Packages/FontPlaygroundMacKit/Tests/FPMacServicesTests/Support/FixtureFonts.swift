import CoreText
import Foundation

struct FontSpec: Encodable, Sendable {
    struct Axis: Encodable, Sendable { var tag: String; var min: Double; var `default`: Double; var max: Double }
    var file: String
    var family: String
    var style = "Regular"
    var postscriptName: String? = nil
    var fullName: String? = nil
    var chars = "abc"
    var notice: String? = nil
    var weightClass = 400
    var os2 = true
    var axes: [Axis] = []
    var stat = true
    var fea: String? = nil
    var localizedFamily: [String: String] = [:]
    var faces: [FontSpec]? = nil
}

enum TestEnv {
    static var appleFonts: Bool { ProcessInfo.processInfo.environment["FP_APPLE_FONTS"] == "1" }
    static var enginePython: String? {
        ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"].flatMap { $0.isEmpty ? nil : $0 }
    }
    static func tag() -> String { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)) }
    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fpmac-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum FixtureFonts {
    struct Unavailable: Error, CustomStringConvertible { let description: String }
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var python: URL? {
        if let path = TestEnv.enginePython { return URL(fileURLWithPath: path) }
        let fallback = packageRoot.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("engine/.venv/bin/python")
        return FileManager.default.isExecutableFile(atPath: fallback.path) ? fallback : nil
    }
    static func build(_ specs: [FontSpec], in directory: URL? = nil) throws -> [URL] {
        guard let python else { throw Unavailable(description: "FP_ENGINE_PYTHON is required for synthetic fonts") }
        let directory = try directory ?? TestEnv.temporaryDirectory()
        struct Request: Encodable { var outDir: String; var fonts: [FontSpec] }
        struct Response: Decodable { var files: [String] }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let process = Process()
        process.executableURL = python
        process.arguments = [packageRoot.appendingPathComponent("TestFixtures/make_fonts.py").path]
        let input = Pipe(); let output = Pipe(); let errors = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: encoder.encode(Request(outDir: directory.path, fonts: specs)))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let error = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Unavailable(description: String(decoding: error, as: UTF8.self))
        }
        return try JSONDecoder().decode(Response.self, from: data).files.map { URL(fileURLWithPath: $0) }
    }
}

enum ProcessScopeFonts {
    static func register(_ url: URL) throws {
        var error: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        let failure = error?.takeRetainedValue()
        if !success, let failure, CFErrorGetCode(failure) != CTFontManagerError.alreadyRegistered.rawValue {
            throw failure
        }
    }
    static func unregister(_ url: URL) {
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
    }
}
