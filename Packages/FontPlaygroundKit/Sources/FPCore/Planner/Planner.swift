import Foundation

public enum Planner {
    /// The pinned material when it covers the code point, otherwise the first material that covers it.
    public static func sourceOf(_ cp: UInt32, coverages: [CodepointSet], rules: [ScriptGroup: Int]) -> Int? {
        if let chosen = rules[ScriptGroup.of(cp)], coverages.indices.contains(chosen), coverages[chosen].contains(cp) {
            return chosen
        }
        return coverages.firstIndex { $0.contains(cp) }
    }

    /// Sweep coverage and script boundaries so cost follows ranges rather than the number of characters.
    public static func plan(coverages: [CodepointSet], rules: [ScriptGroup: Int]) -> Plan {
        var boundaries = coverages.flatMap { $0.ranges.flatMap { [$0.lowerBound, $0.upperBound + 1] } }
        guard let first = boundaries.min(), let last = boundaries.max() else {
            return Plan(assignments: Array(repeating: .empty, count: coverages.count))
        }
        boundaries += ScriptGroupTable.starts.filter { first < $0 && $0 < last }
        boundaries.sort()
        var unique: [UInt32] = []
        unique.reserveCapacity(boundaries.count)
        for boundary in boundaries where unique.last != boundary { unique.append(boundary) }

        var cursors = Array(repeating: 0, count: coverages.count)
        var covered = Array(repeating: false, count: coverages.count)
        var assignments: [[ClosedRange<UInt32>]] = Array(repeating: [], count: coverages.count)
        for interval in 0..<(unique.count - 1) {
            let start = unique[interval]
            let end = unique[interval + 1] - 1
            var firstCovering: Int?
            for index in coverages.indices {
                let ranges = coverages[index].ranges
                while cursors[index] < ranges.count && ranges[cursors[index]].upperBound < start { cursors[index] += 1 }
                covered[index] = cursors[index] < ranges.count && ranges[cursors[index]].lowerBound <= start
                if covered[index] && firstCovering == nil { firstCovering = index }
            }
            guard let fallback = firstCovering else { continue }
            let preferred = rules[ScriptGroup.of(start)]
            let source: Int
            if let preferred, coverages.indices.contains(preferred), covered[preferred] {
                source = preferred
            } else {
                source = fallback
            }
            if let previous = assignments[source].last, previous.upperBound + 1 == start {
                assignments[source][assignments[source].count - 1] = previous.lowerBound...end
            } else {
                assignments[source].append(start...end)
            }
        }
        return Plan(assignments: assignments.map { CodepointSet(ranges: $0) })
    }
}
