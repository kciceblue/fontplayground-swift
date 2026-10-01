import FPCore
import Testing

struct FolderCheckTests {
    @Test("CRIT-2: foreign and missing paths are rejected before storage") func crit2FolderValidation() {
        let folder = "/Users/Someone/Fonts", office = "/Applications/Microsoft Word.app/Contents/Resources/DFonts"
        let probe = FakeFileSystem(files: ["/file"], directories: [folder, office])
        let bad: [(String, FolderCheck.Failure)] = [
            ("", .empty), (" \n", .empty), ("D:/Fonts", .windowsPath),
            (#"C:\Users\Someone\Fonts"#, .windowsPath), (#"\\server\fonts"#, .windowsPath), ("Fonts", .notAbsolute),
            ("/nope", .missing), ("/file", .notADirectory),
        ]
        for (path, failure) in bad { #expect(FolderCheck.check(path, using: probe) == .failure(failure)) }
        #expect(
            FolderCheck.check(folder + "/../Fonts/", using: probe)
                == .success(.init(path: folder, insideApplicationBundle: false)))
        #expect(FolderCheck.check(office, using: probe) == .success(.init(path: office, insideApplicationBundle: true)))
    }
}
