import Foundation

public enum MacServicesConstants {
    public static let bundleIdentifier = "io.github.kciceblue.fontplayground"
    public static let forgedNotice = "Forged with Font Playground"  // engine/merge.py:47, contracts §6
    public static let fontBookBundleIdentifier = "com.apple.FontBook"
    public static let lastResortURL = URL(fileURLWithPath: "/System/Library/Fonts/LastResort.otf")
    public static let sfntMagics: Set<UInt32> = [
        0x0001_0000, 0x4F54_544F /* OTTO */, 0x7472_7565 /* true */,
        0x7474_6366 /* ttcf */,
    ]
    public static let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]  // paths.py:9
    public static let unsupportedFontExtensions: Set<String> = [
        "dfont", "suit", "pfb", "pfa", "pfm", "fon",
        "fnt", "bdf", "pcf", "woff", "woff2",
    ]
}
