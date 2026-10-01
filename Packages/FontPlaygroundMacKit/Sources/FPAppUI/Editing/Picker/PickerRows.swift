import FPCore
import Foundation
import os

struct PickerRowID: Hashable { var section: PickerSection; var text: String; var faceKey: FaceKey? }
enum PickerSection: Hashable { case suggested, all, unshapable }
struct Header: Equatable { var section: PickerSection; var title: String; var accessibilityLabel: String }
struct FamilyRow: Equatable {
    var section: PickerSection
    var family: String
    var face: FaceRecord
    var styles: [FaceRecord]
    var nativeName: String
    var inRecipe: Bool
    var unavailableReason: String?
}
enum PickerRow: Identifiable, Equatable {
    case header(Header), family(FamilyRow)
    var id: PickerRowID {
        switch self {
        case .header(let header): .init(section: header.section, text: header.title, faceKey: nil)
        case .family(let row):
            .init(section: row.section, text: row.family, faceKey: row.section == .suggested ? row.face.key : nil)
        }
    }
    var isSelectable: Bool { if case .family(let row) = self { row.unavailableReason == nil } else { false } }
    var familyRow: FamilyRow? { if case .family(let row) = self { row } else { nil } }
}

enum PickerRows {
    struct Result: Equatable { var rows: [PickerRow]; var listedFamilyCount: Int; var unshapableCount: Int }
    struct Index {
        let families: [String: [FaceRecord]]
        let haystacks: [String: String]
        let familyOrder: [String]
        init(_ catalog: [FaceRecord]) {
            families = Dictionary(grouping: catalog.filter(eligible), by: \.family)
            haystacks = families.mapValues {
                Self.fold(([$0[0].family] + $0.flatMap(\.localNames)).joined(separator: "\n"))
            }
            familyOrder = families.keys.sorted {
                let order = $0.compare($1, options: [.caseInsensitive, .numeric])
                return order == .orderedSame ? $0 < $1 : order == .orderedAscending
            }
        }
        static func fold(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        }
    }
    static func isHidden(_ face: FaceRecord) -> Bool {
        // UI-1/CATALOG-2: defend against records from older scanners as well as today's catalog filter.
        face.hidden || face.family.hasPrefix(".") || face.postscriptName?.hasPrefix(".") == true
            || face.family == "LastResort" || face.family == "System Font"
    }
    static func eligible(_ face: FaceRecord) -> Bool { face.supported && !face.suspiciousCoverage && !isHidden(face) }
    static func canShape(_ face: FaceRecord, language: Language) -> Bool {
        guard let groups = face.shapesGroups else { return true }
        return language.groups.filter(\.needsShaping).allSatisfy { groups.contains($0) }
    }
    static func build(
        catalog: [FaceRecord], language: Language, query: String, context: PickerModel.Context,
        showsUnshapable: Bool, locale: Locale, index: Index? = nil
    ) -> Result {
        let signposter = OSSignposter(subsystem: "io.github.kciceblue.fontplayground", category: "Picker")
        let interval = signposter.beginInterval("PickerRows")
        defer { signposter.endInterval("PickerRows", interval) }
        let index = index ?? Index(catalog), query = Index.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        func matches(_ family: String) -> Bool { query.isEmpty || index.haystacks[family]?.contains(query) == true }
        let recipeFamilies = Set(catalog.filter { context.recipeKeys.contains($0.key) }.map(\.family))
        func row(_ face: FaceRecord, styles: [FaceRecord], section: PickerSection) -> PickerRow {
            let familyFaces = index.families[face.family] ?? [face]
            return .family(
                .init(
                    section: section, family: face.family, face: face, styles: styles,
                    nativeName: face.localNames.first ?? familyFaces.lazy.flatMap(\.localNames).first ?? "",
                    inRecipe: recipeFamilies.contains(face.family),
                    unavailableReason: section == .unshapable ? PickerText.unavailable(language) : nil))
        }
        func styles(_ faces: [FaceRecord]) -> [FaceRecord] {
            faces.sorted {
                if $0.weightClass != $1.weightClass { return $0.weightClass < $1.weightClass }
                if $0.italic != $1.italic { return !$0.italic }
                return $0.style < $1.style
            }
        }
        var suggested: [PickerRow] = [], all: [PickerRow] = [], unshapable: [PickerRow] = []
        var seen: Set<FaceKey> = [], count = 0, cannotShape = 0
        for face in context.suggestions where suggested.count < 3 {
            if eligible(face), Languages.coversWell(face, language), canShape(face, language: language),
                matches(face.family), seen.insert(face.key).inserted
            {
                suggested.append(row(face, styles: [face], section: .suggested))
            }
        }
        for family in index.familyOrder {
            let covering = index.families[family, default: []].filter { Languages.coversWell($0, language) }
            let good = covering.filter { canShape($0, language: language) }
            if !good.isEmpty {
                count += 1
                if matches(family), let face = Smart.defaultFace(good, main: context.main) {
                    all.append(row(face, styles: styles(good), section: .all))
                }
            } else if !covering.isEmpty {
                cannotShape += 1
                if showsUnshapable, matches(family), let face = Smart.defaultFace(covering, main: context.main) {
                    unshapable.append(row(face, styles: styles(covering), section: .unshapable))
                }
            }
        }
        var rows: [PickerRow] = []
        func append(_ values: [PickerRow], section: PickerSection, title: String) {
            guard !values.isEmpty else { return }
            rows.append(
                .header(
                    .init(
                        section: section, title: title,
                        accessibilityLabel: PickerText.headerAccessibilityLabel(title))))
            rows += values
        }
        append(suggested, section: .suggested, title: PickerText.suggested)
        append(all, section: .all, title: PickerText.all(language: language, count: all.count, locale: locale))
        append(
            unshapable, section: .unshapable,
            title: PickerText.unshapable(language: language, count: unshapable.count, locale: locale, checkbox: false))
        return .init(rows: rows, listedFamilyCount: count, unshapableCount: cannotShape)
    }
}
