import Foundation

public struct ReconcileReport: Sendable, Equatable {
    public struct Relocation: Sendable, Equatable {
        public let index: Int
        public let from: FaceKey
        public let to: FaceKey
        public let resolution: FaceResolution

        public init(index: Int, from: FaceKey, to: FaceKey, resolution: FaceResolution) {
            self.index = index; self.from = from; self.to = to; self.resolution = resolution
        }
    }
    public var refreshed: [Int] = []
    public var relocated: [Relocation] = []
    public var nowMissing: [Int] = []
    public var recovered: [Int] = []
    public var changed: Bool { !refreshed.isEmpty || !relocated.isEmpty || !nowMissing.isEmpty || !recovered.isEmpty }

    public init() {}
}
