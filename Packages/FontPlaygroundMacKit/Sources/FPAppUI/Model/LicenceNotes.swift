import FPCore

public enum LicenceNotes {
    public static func lines(for materials: [FaceRecord]) -> [String] {
        let classes = Set(materials.map { $0.licence.licenceClass })
        return [
            (FaceRecord.Licence.LicenceClass.appleSLA, BuildText.appleSLA),
            (.microsoftProduct, BuildText.microsoft), (.unknown, BuildText.unknownLicence),
        ].compactMap { classes.contains($0.0) ? $0.1 : nil }
    }
}
