import os

public enum AppLog {
    public static let subsystem = "io.github.kciceblue.fontplayground"
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let engine = Logger(subsystem: subsystem, category: "engine")
    public static let selfTest = Logger(subsystem: subsystem, category: "self-test")
}
