import Foundation

public enum RuleResolver {
    public static let mainKeepDivisor = 10
    public static let otherKeepDivisor = 2

    public static func counts(for material: Material) -> [ScriptGroup: Int] {
        // CATALOG-2: bogus LastResort-like maps must not capture automatic rules. Explicit pins still win.
        material.isAvailable && !material.face.suspiciousCoverage ? material.face.groupCounts : [:]
    }

    public static func smartSupplier(_ group: ScriptGroup, counts: [FaceKey: [ScriptGroup: Int]], order: [FaceKey])
        -> FaceKey?
    {
        let best = order.map { counts[$0]?[group] ?? 0 }.max() ?? 0
        guard best > 0 else { return nil }
        return order.enumerated().first { index, key in
            (counts[key]?[group] ?? 0) * (index == 0 ? mainKeepDivisor : otherKeepDivisor) >= best
        }?.element
    }

    public static func resolveRules(
        order: [FaceKey], pins: [ScriptGroup: FaceKey], counts: [FaceKey: [ScriptGroup: Int]]
    ) -> [ScriptGroup: Int] {
        var rules: [ScriptGroup: Int] = [:]
        for group in ScriptGroup.allCases {
            if let key = pins[group], let index = order.firstIndex(of: key) {
                rules[group] = index
            } else if let key = smartSupplier(group, counts: counts, order: order) {
                rules[group] = order.firstIndex(of: key)
            }
        }
        return rules
    }
}
