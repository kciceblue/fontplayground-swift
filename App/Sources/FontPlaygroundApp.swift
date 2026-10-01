import FPAppUI
import SwiftUI

/// Launcher owns the process entry point.
struct FontPlaygroundApp: App {
    @NSApplicationDelegateAdaptor(FPAppDelegate.self) private var delegate
    var body: some Scene {
        Settings { SettingsView(model: delegate.model) }
            .commands { AppCommands(model: delegate.model) }
    }
}
