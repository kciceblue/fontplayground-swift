import SwiftUI

public struct ReportSheet: View {
    let text: String
    let system: any SystemActions
    @Environment(\.dismiss) private var dismiss
    public init(text: String, system: any SystemActions) { self.text = text; self.system = system }
    public var body: some View {
        VStack(alignment: .leading) {
            Text(ShellText.reportTitle).accessibilityAddTraits(.isHeader).font(.headline)
            ScrollView {
                Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(
                    maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(ShellText.copy) { system.copyToPasteboard(text) }; Spacer();
                Button(ShellText.done) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding().frame(minWidth: 520, idealWidth: 650, minHeight: 360, idealHeight: 520)
    }
}
