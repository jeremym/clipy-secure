import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.clipysecure"

    static let database = Logger(subsystem: subsystem, category: "database")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let general = Logger(subsystem: subsystem, category: "general")
}
