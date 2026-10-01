import Foundation

public enum ForgedMarker {
    public static func isForged(fileAt url: URL) -> Bool {
        NameTable.tables(forFontAt: url).contains { table in
            table.strings(nameID: 0).contains { $0.hasPrefix(MacServicesConstants.forgedNotice) }
        }
    }
}
