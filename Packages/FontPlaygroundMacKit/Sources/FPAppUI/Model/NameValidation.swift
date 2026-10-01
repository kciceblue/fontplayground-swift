import FPCore

public enum NameValidation {
    public static func problem(family: String, style: String) -> String? {
        let family = Naming.cleanName(family), style = Naming.cleanName(style)
        if style.hasPrefix(".") { return BuildText.styleLeadingDot }
        if family.count > 63 { return BuildText.nameTooLong }
        if style.count > 63 { return BuildText.styleTooLong }
        return nil
    }
}
