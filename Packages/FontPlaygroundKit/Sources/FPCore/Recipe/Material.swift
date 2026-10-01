import Foundation

public struct Material: Sendable, Equatable, Codable {
    public enum Availability: String, Sendable, Codable { case available, fileGone, notFound }
    public var face: FaceRecord
    public var weight: Int?
    public var scale: Double?
    public var availability: Availability
    public var isAvailable: Bool { availability == .available }
    public var key: FaceKey { face.key }

    public init(face: FaceRecord, weight: Int? = nil, scale: Double? = nil, availability: Availability = .available) {
        self.face = face; self.weight = weight; self.scale = scale; self.availability = availability
    }
}

public struct RecipeNames: Sendable, Equatable, Codable {
    public var family: String
    public var style: String
    public var familyEdited: Bool
    public var styleEdited: Bool

    public init(
        family: String = "Forged", style: String = "Regular", familyEdited: Bool = false, styleEdited: Bool = false
    ) {
        self.family = family; self.style = style; self.familyEdited = familyEdited; self.styleEdited = styleEdited
    }
}
