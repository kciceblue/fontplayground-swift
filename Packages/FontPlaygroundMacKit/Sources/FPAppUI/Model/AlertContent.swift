import Foundation
import SwiftUI

public struct AlertButton: Identifiable {
    public let id = UUID()
    public var title: String
    public var role: ButtonRole?
    public var isDefault: Bool
    public var action: @MainActor () -> Void
    public init(
        title: String, role: ButtonRole? = nil, isDefault: Bool = false, action: @escaping @MainActor () -> Void
    ) { self.title = title; self.role = role; self.isDefault = isDefault; self.action = action }
}
public struct AlertContent: Identifiable {
    public let id = UUID()
    public var title: String
    public var message: String?
    public var buttons: [AlertButton]
    public init(title: String, message: String? = nil, buttons: [AlertButton]) {
        self.title = title; self.message = message; self.buttons = buttons
    }
}
public enum SheetContent: Identifiable, Equatable {
    case report(String)
    public var id: String {
        switch self {
        case .report(let text): "report:" + text
        }
    }
}
