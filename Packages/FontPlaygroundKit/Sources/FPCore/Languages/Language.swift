import Foundation

public struct Language: Sendable, Hashable {
    public struct Minimum: Sendable, Hashable {
        public let group: ScriptGroup
        public let count: Int
        public init(group: ScriptGroup, count: Int) { self.group = group; self.count = count }
    }
    public let id: LanguageID
    public let groups: [ScriptGroup]
    public let minimums: [Minimum]
    public let markers: String
    public let pickerSample: String
    public let textSample: String

    public init(
        id: LanguageID, groups: [ScriptGroup], minimums: [Minimum], markers: String, pickerSample: String,
        textSample: String
    ) {
        self.id = id; self.groups = groups; self.minimums = minimums; self.markers = markers
        self.pickerSample = pickerSample; self.textSample = textSample
    }
}

public enum RoleTitle: Sendable, Equatable {
    case addsNothing, fillsInTheRest, forLanguages([LanguageID])
}
