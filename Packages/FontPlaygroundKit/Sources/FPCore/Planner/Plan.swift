import Foundation

public struct Plan: Sendable, Equatable {
    public static let empty = Plan(assignments: [])
    public let assignments: [CodepointSet]

    public init(assignments: [CodepointSet]) { self.assignments = assignments }

    public var totalCodepoints: Int { assignments.reduce(0) { $0 + $1.count } }

    public func source(of cp: UInt32) -> Int? {
        assignments.firstIndex { $0.contains(cp) }
    }

    public func tallies() -> [[ScriptGroup: Int]] {
        assignments.map { ScriptGroup.counts(in: $0) }
    }
}
