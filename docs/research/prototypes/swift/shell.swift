// Prototype: native shell side of the hybrid design.
// 1) spawn the Python engine helper, stream JSON-lines progress, decode the report
// 2) register the forged TTF in *process* scope and check CoreText draws from it
// 3) enumerate the font catalog through CoreText (what a native picker would list)
import Foundation
import CoreText

struct Event: Decodable {
    let event: String
    let stage: String?
    let fraction: Double?
    let message: String?
    let report: Report?
}
struct Report: Decodable {
    struct Material: Decodable { let name: String; let codepoints: Int; let groups: [String]; let warnings: [String] }
    let materials: [Material]; let total_codepoints: Int; let total_glyphs: Int; let warnings: [String]; let output_path: String
}

let args = CommandLine.arguments
let python = args[1], helper = args[2], requestPath = args[3]
let t0 = Date()
let p = Process()
p.executableURL = URL(fileURLWithPath: python)
p.arguments = [helper]
let inPipe = Pipe(), outPipe = Pipe()
p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = FileHandle.nullDevice
try p.run()
inPipe.fileHandleForWriting.write(try Data(contentsOf: URL(fileURLWithPath: requestPath)))
try inPipe.fileHandleForWriting.close()
var report: Report?
var buffer = Data()
let dec = JSONDecoder()
while true {
    let chunk = outPipe.fileHandleForReading.availableData
    if chunk.isEmpty { break }
    buffer.append(chunk)
    while let nl = buffer.firstIndex(of: 0x0A) {
        let line = buffer[buffer.startIndex..<nl]; buffer = Data(buffer[(nl + 1)...])
        let ev = try dec.decode(Event.self, from: line)
        switch ev.event {
        case "progress": print(String(format: "[%5.1fs] %@ %.0f%%", Date().timeIntervalSince(t0), ev.stage ?? "", (ev.fraction ?? 0) * 100))
        case "done": report = ev.report
        default: print("error:", ev.message ?? "?")
        }
    }
}
p.waitUntilExit()
guard let r = report else { print("no report, exit", p.terminationStatus); exit(1) }
print("report: \(r.total_codepoints) chars, \(r.total_glyphs) glyphs -> \(r.output_path)")

// 2) process-scope registration (never user/persistent scope in this experiment)
let url = URL(fileURLWithPath: r.output_path) as CFURL
var err: Unmanaged<CFError>?
let ok = CTFontManagerRegisterFontsForURL(url, .process, &err)
print("register process scope:", ok)
if let descs = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor], let d = descs.first {
    let font = CTFontCreateWithFontDescriptor(d, 30, nil)
    let name = CTFontCopyFamilyName(font) as String
    let sample = Array("Hamburgefonstiv 你好世界 漢字 かな".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: sample.count)
    let all = CTFontGetGlyphsForCharacters(font, sample, &glyphs, sample.count)
    print("CoreText family=\(name) allGlyphsFound=\(all) missing=\(glyphs.filter { $0 == 0 }.count) (spaces count as found)")
    // run-level check: which font does CoreText actually use for each run of an attributed string?
    let attr = CFAttributedStringCreate(nil, "Hamburg 你好 かな" as CFString, [kCTFontAttributeName: font] as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attr)
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let attrs = CTRunGetAttributes(run) as NSDictionary
        let f = attrs[kCTFontAttributeName] as! CTFont
        print("  run font:", CTFontCopyPostScriptName(f) as String, "glyphs:", CTRunGetGlyphCount(run))
    }
}
CTFontManagerUnregisterFontsForURL(url, .process, nil)

// 3) CoreText catalog
let t1 = Date()
let urls = (CTFontManagerCopyAvailableFontURLs() as? [URL]) ?? []
let dirs = ["/System/Library/Fonts/", "/Library/Fonts/", NSHomeDirectory() + "/Library/Fonts/"]
let outside = urls.filter { u in !dirs.contains { u.path.hasPrefix($0) } }
print(String(format: "CoreText available font URLs: %d (%.2fs); outside the 3 scanned dirs: %d", urls.count, Date().timeIntervalSince(t1), outside.count))
for u in outside.prefix(6) { print("   ", u.path) }
let fams = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
print("CoreText families:", fams.count)
