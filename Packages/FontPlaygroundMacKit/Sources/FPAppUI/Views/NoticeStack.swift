import SwiftUI

public struct NoticeStack: View {
    let model: AppModel
    public init(model: AppModel) { self.model = model }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.notices) { notice in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(notice.text).textSelection(.enabled)
                        ForEach(notice.replacements.indices, id: \.self) { index in
                            let replacement = notice.replacements[index]
                            Button(ShellText.useReplacement(name: replacement.replacementName)) {
                                model.applyReplacement(replacement)
                            }.disabled(model.isBuilding)
                        }
                        if notice.revealURL != nil { Button(ShellText.showInFinder) { model.revealNotice(notice) } }
                    }
                    Spacer(minLength: 8)
                    IconButton(symbol: "xmark", label: ShellText.dismiss) { model.dismissNotice(notice.id) }
                }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(model.notices.isEmpty ? 0 : 12)
    }
}
