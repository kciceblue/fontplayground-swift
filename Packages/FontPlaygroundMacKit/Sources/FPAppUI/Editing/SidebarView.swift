import SwiftUI

public struct SidebarView: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(model: AppModel) { self.model = model }
    public var body: some View {
        Group {
            if model.pickRequest != nil {
                FontPickerView(model: model).transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                RecipeColumn(model: model)
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.pickRequest != nil)
    }
}
