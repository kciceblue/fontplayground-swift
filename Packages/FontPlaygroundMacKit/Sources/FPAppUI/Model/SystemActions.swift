import AppKit
import FPCore

public enum SystemEvent: Sendable { case didBecomeActive, displayOptionsChanged }
public struct ActivityToken: Hashable, Sendable { public let id: UUID; public init(id: UUID = UUID()) { self.id = id } }
@MainActor public protocol SystemActions: AnyObject {
    var isAppActive: Bool { get }
    var increaseContrast: Bool { get }
    var isFontBookAvailable: Bool { get }
    var events: AsyncStream<SystemEvent> { get }
    func applyAppearance(_ appearance: AppSettings.Appearance)
    func reveal(_ urls: [URL])
    func openFontBook()
    func openInFontBook(_ file: URL)
    func openURL(_ url: URL)
    func requestAttention()
    func setDockBadge(_ text: String?)
    func beginActivity(reason: String) -> ActivityToken
    func endActivity(_ token: ActivityToken)
    func showAboutPanel(credits: String)
    func copyToPasteboard(_ text: String)
    /// The language FPAppUI's strings use in this process (localisation.md D5).
    var runningLanguage: String { get }
    /// The user's system-wide language list, without the app's own override.
    var systemLanguages: [String] { get }
    /// `AppleLanguages` in the app's own defaults domain only; nil when the app follows the system.
    var languageOverride: [String]? { get }
    func setLanguageOverride(_ languages: [String]?)
    func terminate()
    /// Opens the app again once this process has exited.
    func relaunchAfterExit()
}
@MainActor final class LiveSystemActions: SystemActions {
    var isAppActive: Bool { NSApp.isActive }
    var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    var fontBook: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.FontBook") }
    var isFontBookAvailable: Bool { fontBook != nil }
    let events: AsyncStream<SystemEvent>
    private var activities: [UUID: NSObjectProtocol] = [:]
    private let notifications: SystemNotificationTokens
    private let defaults: UserDefaults
    private let domain: String
    init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "") {
        self.defaults = defaults; self.domain = domain
        let stream = AsyncStream<SystemEvent>.makeStream(); events = stream.stream
        notifications = SystemNotificationTokens(continuation: stream.continuation)
    }
    func applyAppearance(_ appearance: AppSettings.Appearance) {
        switch appearance {
        case .system: NSApp.appearance = nil;
        case .light: NSApp.appearance = NSAppearance(named: .aqua);
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    func openFontBook() {
        if let url = fontBook {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    func openInFontBook(_ file: URL) {
        if let url = fontBook {
            NSWorkspace.shared.open([file], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    func openURL(_ url: URL) { NSWorkspace.shared.open(url) }
    func requestAttention() { if !isAppActive { NSApp.requestUserAttention(.informationalRequest) } }
    func setDockBadge(_ text: String?) { NSApp.dockTile.badgeLabel = text }
    func beginActivity(reason: String) -> ActivityToken {
        let token = ActivityToken();
        activities[token.id] = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: reason);
        return token
    }
    func endActivity(_ token: ActivityToken) {
        if let activity = activities.removeValue(forKey: token.id) { ProcessInfo.processInfo.endActivity(activity) }
    }
    func showAboutPanel(credits: String) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: credits,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor,
                ])
        ])
    }
    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    var runningLanguage: String { LocalizationSupport.runningLanguage }
    var systemLanguages: [String] {
        defaults.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
    }
    var languageOverride: [String]? { defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String] }
    func setLanguageOverride(_ languages: [String]?) {
        if let languages {
            defaults.set(languages, forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }
    func terminate() { NSApp.terminate(nil) }
    func relaunchAfterExit() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = Self.relaunchArguments(pid: getpid(), bundlePath: Bundle.main.bundlePath)
        do { try process.run() } catch {
            AppLog.app.error("Couldn't reopen the app: \(error.localizedDescription, privacy: .public)")
        }
    }
    /// A waiter that outlives the app: it polls until this process has gone, then opens the bundle again.
    /// The path travels as an argument, so spaces in "Font Playground.app" need no quoting.
    static func relaunchArguments(pid: Int32, bundlePath: String) -> [String] {
        [
            "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open \"$2\"",
            "fp-relaunch", String(pid), bundlePath,
        ]
    }
}
// Notification ownership is independent of actor isolation, so teardown always unregisters both centers.
private final class SystemNotificationTokens {
    let observations: [(NotificationCenter, NSObjectProtocol)]
    let continuation: AsyncStream<SystemEvent>.Continuation
    @MainActor init(continuation: AsyncStream<SystemEvent>.Continuation) {
        self.continuation = continuation
        let app = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        observations = [
            (
                app,
                app.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
                    continuation.yield(.didBecomeActive)
                }
            ),
            (
                workspace,
                workspace.addObserver(
                    forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: nil
                ) { _ in continuation.yield(.displayOptionsChanged) }
            ),
        ]
    }
    deinit { for (center, token) in observations { center.removeObserver(token) }; continuation.finish() }
}
