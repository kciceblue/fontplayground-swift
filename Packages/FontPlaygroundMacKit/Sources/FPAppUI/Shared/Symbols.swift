import SwiftUI

public struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    public init(symbol: String, label: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.action = action
    }
    public var body: some View {
        Button(action: action) { Image(systemName: symbol) }.buttonStyle(.borderless).accessibilityLabel(Text(label))
            .help(Text(label))
    }
}
public struct DecorativeSymbol: View {
    let symbol: String
    public init(_ symbol: String) { self.symbol = symbol }
    public var body: some View { Image(systemName: symbol).accessibilityHidden(true) }
}
