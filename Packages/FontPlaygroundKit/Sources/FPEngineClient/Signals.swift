import Foundation

enum Signals {
    static let terminate: Int32 = SIGTERM
    static let forceKill: Int32 = SIGKILL
    static let interrupted: Set<Int32> = [SIGTERM, SIGINT, SIGKILL, SIGHUP]
    private static let ignored: Void = { _ = signal(SIGPIPE, SIG_IGN) }()
    static func ignoreSIGPIPE() { _ = ignored }
    static func send(_ signal: Int32, to pid: Int32) { _ = kill(pid, signal) }
    static func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
}
