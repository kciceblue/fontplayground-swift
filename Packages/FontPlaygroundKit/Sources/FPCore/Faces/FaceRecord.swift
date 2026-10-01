import Foundation

public struct FaceRecord: Codable, Sendable, Hashable {
    public enum Outline: String, Codable, Sendable { case glyf, cff = "CFF", cff2 = "CFF2", none }
    public enum Embedding: String, Codable, Sendable {
        case installable, editable, previewPrint = "preview-print", restricted
    }
    public struct Axis: Codable, Sendable, Hashable {
        public var tag: String
        public var min: Double
        public var `default`: Double
        public var max: Double
        public init(tag: String, min: Double, default: Double, max: Double) {
            self.tag = tag; self.min = min; self.default = `default`; self.max = max
        }
    }
    public struct OTScripts: Codable, Sendable, Hashable {
        public var gsub: [String]
        public var gpos: [String]
        public init(gsub: [String] = [], gpos: [String] = []) { self.gsub = gsub; self.gpos = gpos }
        private enum CodingKeys: String, CodingKey { case gsub, gpos }
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            gsub = try values.decodeIfPresent([String].self, forKey: .gsub) ?? []
            gpos = try values.decodeIfPresent([String].self, forKey: .gpos) ?? []
        }
    }
    public struct AATFlags: Codable, Sendable, Hashable {
        public var morx: Bool
        public var kerx: Bool
        public var kernV1: Bool
        public var trak: Bool
        public init(morx: Bool = false, kerx: Bool = false, kernV1: Bool = false, trak: Bool = false) {
            self.morx = morx; self.kerx = kerx; self.kernV1 = kernV1; self.trak = trak
        }
        private enum CodingKeys: String, CodingKey { case morx, kerx, kernV1 = "kern_v1", trak }
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            morx = try values.decodeIfPresent(Bool.self, forKey: .morx) ?? false
            kerx = try values.decodeIfPresent(Bool.self, forKey: .kerx) ?? false
            kernV1 = try values.decodeIfPresent(Bool.self, forKey: .kernV1) ?? false
            trak = try values.decodeIfPresent(Bool.self, forKey: .trak) ?? false
        }
    }
    public struct Licence: Codable, Sendable, Hashable {
        public enum LicenceClass: String, Codable, Sendable {
            case open, appleSLA = "apple-sla", microsoftProduct = "microsoft-product", unknown
            public init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer().decode(String.self)
                self = Self(rawValue: value) ?? .unknown
            }
        }
        public var licenceClass: LicenceClass
        public var vendorID: String?
        public var notice: String?
        public init(licenceClass: LicenceClass = .unknown, vendorID: String? = nil, notice: String? = nil) {
            self.licenceClass = licenceClass; self.vendorID = vendorID; self.notice = notice
        }
        private enum CodingKeys: String, CodingKey { case licenceClass = "class", vendorID = "vendor_id", notice }
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            licenceClass = try values.decodeIfPresent(LicenceClass.self, forKey: .licenceClass) ?? .unknown
            vendorID = try values.decodeIfPresent(String.self, forKey: .vendorID)
            notice = try values.decodeIfPresent(String.self, forKey: .notice)
        }
        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(licenceClass, forKey: .licenceClass)
            try values.encode(vendorID, forKey: .vendorID)
            try values.encode(notice, forKey: .notice)
        }
    }
    public var path: String
    public var index: Int
    public var size: Int
    public var mtime: Double
    public var family: String
    public var style: String
    public var fullName: String
    public var postscriptName: String?
    public var localNames: [String]
    public var outline: Outline
    public var isCollection: Bool
    public var isVariable: Bool
    public var axes: [Axis]
    public var weightClass: Int
    public var italic: Bool
    public var upem: Int
    public var glyphCount: Int
    public var groupCounts: [ScriptGroup: Int]
    public var embedding: Embedding
    public var fsType: Int?
    public var hasColor: Bool
    public var supported: Bool
    public var unsupportedReason: String?
    public var hidden: Bool
    public var suspiciousCoverage: Bool
    public var otScripts: OTScripts
    public var aat: AATFlags
    public var shapesGroups: Set<ScriptGroup>?
    public var licence: Licence
    public var hasOS2: Bool
    public var isForged: Bool
    public var fontRevision: String

    public var coverage: CodepointSet {
        didSet { unshaped = unshaped.intersection(coverage); refreshCoverage() }
    }
    public var unshaped: CodepointSet {
        didSet { unshaped = unshaped.intersection(coverage); refreshCoverage() }
    }
    /// The characters this face can draw after forging (engine-metadata.md S4).
    public private(set) var plannableCoverage: CodepointSet
    public var key: FaceKey { FaceKey(path: path, index: index) }
    public var displayName: String { "\(family) \(style)" }
    public var identity: PortableFaceIdentity {
        PortableFaceIdentity(postscriptName: postscriptName, family: family, style: style, path: path, index: index)
    }
    public var hasWeightAxis: Bool { axes.contains { $0.tag == "wght" } }
    public func count(of group: ScriptGroup) -> Int { groupCounts[group] ?? 0 }
    public func canShape(_ group: ScriptGroup) -> Bool {
        // ENGINE-2: a missing shaping field means unknown, so older records never block.
        !group.needsShaping || (shapesGroups?.contains(group) ?? true)
    }
    private mutating func refreshCoverage() {
        plannableCoverage = coverage.subtracting(unshaped)
        groupCounts = ScriptGroup.counts(in: plannableCoverage)
    }

    public init(
        path: String, index: Int = 0, family: String, style: String = "Regular", coverage: CodepointSet,
        unshaped: CodepointSet = .empty, weightClass: Int = 400, italic: Bool = false, upem: Int = 1000,
        glyphCount: Int? = nil, outline: Outline = .glyf, axes: [Axis] = [], hasColor: Bool = false,
        embedding: Embedding = .installable, size: Int = 1, mtime: Double = 1.0, postscriptName: String? = nil,
        fullName: String? = nil, localNames: [String] = [], isCollection: Bool = false, isVariable: Bool? = nil,
        groupCounts: [ScriptGroup: Int]? = nil, supported: Bool? = nil, unsupportedReason: String? = nil,
        hidden: Bool = false, suspiciousCoverage: Bool = false, shapesGroups: Set<ScriptGroup>? = nil,
        fsType: Int? = nil, otScripts: OTScripts = .init(), aat: AATFlags = .init(), licence: Licence = .init(),
        hasOS2: Bool = true, isForged: Bool = false, fontRevision: String = "1.000"
    ) {
        let reason = unsupportedReason ?? Self.supportReason(outline: outline, hasColor: hasColor)
        self.coverage = coverage
        self.unshaped = unshaped.intersection(coverage)
        plannableCoverage = coverage.subtracting(self.unshaped)
        self.path = path
        self.index = index
        self.size = size
        self.mtime = mtime
        self.family = family
        self.style = style
        self.fullName = fullName ?? "\(family) \(style)"
        self.postscriptName = postscriptName
        self.localNames = localNames
        self.outline = outline
        self.isCollection = isCollection
        self.isVariable = isVariable ?? !axes.isEmpty
        self.axes = axes
        self.weightClass = weightClass
        self.italic = italic
        self.upem = upem
        self.glyphCount = glyphCount ?? coverage.count + 1
        self.groupCounts = (groupCounts ?? ScriptGroup.counts(in: plannableCoverage)).filter { $0.value != 0 }
        self.embedding = embedding
        self.fsType = fsType
        self.hasColor = hasColor
        self.supported = supported ?? (reason == nil)
        self.unsupportedReason = reason
        self.hidden = hidden
        self.suspiciousCoverage = suspiciousCoverage
        self.otScripts = otScripts
        self.aat = aat
        self.shapesGroups = shapesGroups
        self.licence = licence
        self.hasOS2 = hasOS2
        self.isForged = isForged
        self.fontRevision = fontRevision
    }
    private static func supportReason(outline: Outline, hasColor: Bool) -> String? {
        if outline == .none { return "bitmap-only font (no outlines)" }
        if outline == .cff2 { return "CFF2 outlines are not supported" }
        if hasColor { return "colour fonts are not supported" }
        return nil
    }
    private enum CodingKeys: String, CodingKey {
        case path
        case index
        case size
        case mtime
        case family
        case style
        case fullName = "full_name"
        case postscriptName = "postscript_name"
        case localNames = "local_names"
        case outline
        case isCollection = "is_collection"
        case isVariable = "is_variable"
        case axes
        case weightClass = "weight_class"
        case italic
        case upem
        case glyphCount = "glyph_count"
        case groupCounts = "group_counts"
        case embedding
        case fsType = "fs_type"
        case hasColor = "has_color"
        case supported
        case unsupportedReason = "unsupported_reason"
        case hidden
        case suspiciousCoverage = "suspicious_coverage"
        case otScripts = "ot_scripts"
        case aat
        case shapesGroups = "shapes_groups"
        case licence
        case hasOS2 = "has_os2"
        case isForged = "is_forged"
        case fontRevision = "font_revision"
        case coverage
        case unshaped
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(path, forKey: .path)
        try values.encode(index, forKey: .index)
        try values.encode(size, forKey: .size)
        try values.encode(mtime, forKey: .mtime)
        try values.encode(family, forKey: .family)
        try values.encode(style, forKey: .style)
        try values.encode(fullName, forKey: .fullName)
        try values.encode(postscriptName, forKey: .postscriptName)
        try values.encode(localNames, forKey: .localNames)
        try values.encode(outline, forKey: .outline)
        try values.encode(isCollection, forKey: .isCollection)
        try values.encode(isVariable, forKey: .isVariable)
        try values.encode(axes, forKey: .axes)
        try values.encode(weightClass, forKey: .weightClass)
        try values.encode(italic, forKey: .italic)
        try values.encode(upem, forKey: .upem)
        try values.encode(glyphCount, forKey: .glyphCount)
        try values.encode(
            Dictionary(uniqueKeysWithValues: groupCounts.map { ($0.key.rawValue, $0.value) }), forKey: .groupCounts)
        try values.encode(embedding, forKey: .embedding)
        try values.encode(fsType, forKey: .fsType)
        try values.encode(hasColor, forKey: .hasColor)
        try values.encode(supported, forKey: .supported)
        try values.encode(unsupportedReason, forKey: .unsupportedReason)
        try values.encode(hidden, forKey: .hidden)
        try values.encode(suspiciousCoverage, forKey: .suspiciousCoverage)
        try values.encode(otScripts, forKey: .otScripts)
        try values.encode(aat, forKey: .aat)
        try values.encode(shapesGroups.map { $0.sorted().map(\.rawValue) }, forKey: .shapesGroups)
        try values.encode(licence, forKey: .licence)
        try values.encode(hasOS2, forKey: .hasOS2)
        try values.encode(isForged, forKey: .isForged)
        try values.encode(fontRevision, forKey: .fontRevision)
        try values.encode(coverage, forKey: .coverage)
        try values.encode(unshaped, forKey: .unshaped)
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let counts = try values.decodeIfPresent([String: Int].self, forKey: .groupCounts)
        let groupCounts = counts.map {
            Dictionary(
                uniqueKeysWithValues: $0.compactMap { key, value in
                    ScriptGroup(rawValue: key).map { ($0, value) }
                })
        }
        let shaped = try values.decodeIfPresent([String].self, forKey: .shapesGroups)
        let shapesGroups = shaped.map { Set($0.compactMap(ScriptGroup.init(rawValue:))) }
        self.init(
            path: try values.decode(String.self, forKey: .path),
            index: try values.decode(Int.self, forKey: .index),
            family: try values.decode(String.self, forKey: .family),
            style: try values.decode(String.self, forKey: .style),
            coverage: try values.decode(CodepointSet.self, forKey: .coverage),
            unshaped: try values.decodeIfPresent(CodepointSet.self, forKey: .unshaped) ?? .empty,
            weightClass: try values.decodeIfPresent(Int.self, forKey: .weightClass) ?? 400,
            italic: try values.decodeIfPresent(Bool.self, forKey: .italic) ?? false,
            upem: try values.decodeIfPresent(Int.self, forKey: .upem) ?? 1000,
            glyphCount: try values.decodeIfPresent(Int.self, forKey: .glyphCount),
            outline: try values.decodeIfPresent(Outline.self, forKey: .outline) ?? .glyf,
            axes: try values.decodeIfPresent([Axis].self, forKey: .axes) ?? [],
            hasColor: try values.decodeIfPresent(Bool.self, forKey: .hasColor) ?? false,
            embedding: try values.decodeIfPresent(Embedding.self, forKey: .embedding) ?? .installable,
            size: try values.decodeIfPresent(Int.self, forKey: .size) ?? 0,
            mtime: try values.decodeIfPresent(Double.self, forKey: .mtime) ?? 0,
            postscriptName: try values.decodeIfPresent(String.self, forKey: .postscriptName),
            fullName: try values.decodeIfPresent(String.self, forKey: .fullName),
            localNames: try values.decodeIfPresent([String].self, forKey: .localNames) ?? [],
            isCollection: try values.decodeIfPresent(Bool.self, forKey: .isCollection) ?? false,
            isVariable: try values.decodeIfPresent(Bool.self, forKey: .isVariable),
            groupCounts: groupCounts,
            supported: try values.decodeIfPresent(Bool.self, forKey: .supported),
            unsupportedReason: try values.decodeIfPresent(String.self, forKey: .unsupportedReason),
            hidden: try values.decodeIfPresent(Bool.self, forKey: .hidden) ?? false,
            suspiciousCoverage: try values.decodeIfPresent(Bool.self, forKey: .suspiciousCoverage) ?? false,
            shapesGroups: shapesGroups,
            fsType: try values.decodeIfPresent(Int.self, forKey: .fsType),
            otScripts: try values.decodeIfPresent(OTScripts.self, forKey: .otScripts) ?? .init(),
            aat: try values.decodeIfPresent(AATFlags.self, forKey: .aat) ?? .init(),
            licence: try values.decodeIfPresent(Licence.self, forKey: .licence) ?? .init(),
            hasOS2: try values.decodeIfPresent(Bool.self, forKey: .hasOS2) ?? true,
            isForged: try values.decodeIfPresent(Bool.self, forKey: .isForged) ?? false,
            fontRevision: try values.decodeIfPresent(String.self, forKey: .fontRevision) ?? ""
        )
    }
}
