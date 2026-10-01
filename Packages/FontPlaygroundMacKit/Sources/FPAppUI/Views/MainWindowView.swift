import SwiftUI

public struct MainWindowView: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }
    public var body: some View {
        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            SidebarView(model: model).focusSection().navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 420)
        } detail: {
            VStack(spacing: 0) {
                NoticeStack(model: model);
                PreviewPane(model: model).focusSection().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 360)
            .safeAreaInset(edge: .bottom) { ActionBarView(model: model).frame(minWidth: 360).focusSection() }
            // UI-15: keep the inspector inside detail so its width is counted once when the sidebar collapses.
            .inspector(isPresented: $model.inspectorPresented) {
                AdvancedInspectorView(model: model).focusSection().inspectorColumnWidth(min: 260, ideal: 300, max: 420)
            }
            // UI-15: the collapsed native inspector can retain its ideal width in minimum-size probes.
            .frame(minWidth: model.inspectorPresented ? 660 : 360, maxWidth: .infinity)
        }
        // UI-15: a saved-open inspector must not let transient sidebar measurements enlarge the restored window.
        .frame(minWidth: model.inspectorPresented ? 660 : 640, maxWidth: .infinity)
        // UI-15: Animated inspector/split-view resizing can cycle indefinitely in AppKit layout on macOS 27.
        .transaction { $0.disablesAnimations = true }
        .toolbar {
            ToolbarItem {
                IconButton(
                    symbol: "sidebar.trailing",
                    label: model.inspectorPresented ? ShellText.hideAdvanced : ShellText.showAdvanced
                ) { model.toggleAdvanced() }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in model.handleDrop(urls) }
        .contentAlert($model.alert)
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .report(let text): ReportSheet(text: text, system: model.services.system)
            }
        }
    }
}
