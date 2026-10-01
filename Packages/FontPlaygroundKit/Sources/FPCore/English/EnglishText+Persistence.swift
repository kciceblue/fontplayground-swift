import Foundation

extension EnglishText {
    public static func unresolvedSummary(_ report: LoadReport) -> String {
        let count = report.unresolved.count
        guard count > 0 else { return "" }
        return "\(count) \(count == 1 ? "font" : "fonts") could not be found: "
            + report.unresolved.map(\.displayName).joined(separator: ", ")
    }

    public static func replacementOffer(missing: String, replacement: String) -> String {
        "\(missing) isn't on this Mac. Use \(replacement) instead?"
    }
}
