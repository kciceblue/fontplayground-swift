import FPEngineClient

public enum AboutCredits {
    public static func make(hello: EngineHello?, acknowledgements: String?) -> String {
        var parts = [ShellText.licenceNote]
        if let hello {
            parts.append(
                ShellText.engineVersion(engine: hello.fpengineVersion, fonttools: hello.fonttools, python: hello.python)
            )
        }
        if let acknowledgements, !acknowledgements.isEmpty {
            parts.append(ShellText.acknowledgements + "\n" + acknowledgements)
        }
        return parts.joined(separator: "\n\n")
    }
}
