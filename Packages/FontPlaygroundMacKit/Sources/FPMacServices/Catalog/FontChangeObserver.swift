import CoreText
import Foundation

final class FontChangeObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [(NotificationCenter, any NSObjectProtocol)] = []
    init(centers: [NotificationCenter], changed: @escaping @Sendable () -> Void) {
        for center in centers {
            let token = center.addObserver(
                forName: Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String),
                object: nil, queue: nil
            ) { _ in changed() }
            tokens.append((center, token))
        }
    }
    func stop() {
        let old = lock.withLock {
            let old = tokens; tokens = []; return old
        }
        for (center, token) in old { center.removeObserver(token) }
    }
    deinit { stop() }
}
