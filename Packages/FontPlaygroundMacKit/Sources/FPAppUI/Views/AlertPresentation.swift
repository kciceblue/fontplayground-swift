import SwiftUI

extension View {
    /// Presents an `AlertContent` on the window that shows this view; the binding clears before a button's action runs.
    func contentAlert(_ content: Binding<AlertContent?>) -> some View {
        alert(
            content.wrappedValue?.title ?? "",
            isPresented: Binding(get: { content.wrappedValue != nil }, set: { if !$0 { content.wrappedValue = nil } }),
            presenting: content.wrappedValue
        ) { alert in
            ForEach(alert.buttons) { button in
                Button(button.title, role: button.role) {
                    content.wrappedValue = nil; button.action()
                }.keyboardShortcut(button.isDefault ? .defaultAction : nil)
            }
        } message: { alert in
            if let message = alert.message { Text(message) }
        }
    }
}
