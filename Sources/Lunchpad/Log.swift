import Foundation
import os

/// Lunchpad's diagnostics.
///
/// A packaged app's standard output is discarded, so messages go to the unified log, where they
/// can be read with `log stream --predicate 'subsystem == "com.arichyx.Lunchpad"'`. When standard
/// output is a terminal, such as `Scripts/dev-run.sh -f`, messages are echoed there as well.
enum Log {
    static let subsystem = "com.arichyx.Lunchpad"

    static let lifecycle = LunchpadLogger(category: "lifecycle")
    static let catalog = LunchpadLogger(category: "catalog")
    static let gesture = LunchpadLogger(category: "gesture")
    static let hotKey = LunchpadLogger(category: "hot-key")
    static let layout = LunchpadLogger(category: "layout")
    static let launch = LunchpadLogger(category: "launch")
}

struct LunchpadLogger: Sendable {
    private static let echoesToTerminal = isatty(STDOUT_FILENO) != 0

    private let logger: Logger

    init(category: String) {
        logger = Logger(subsystem: Log.subsystem, category: category)
    }

    /// A normal event that is worth keeping in the persisted log.
    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        echo(message)
    }

    /// A recoverable failure.
    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        echo("⚠️ " + message)
    }

    /// High-frequency diagnostics enabled explicitly, such as `LUNCHPAD_GESTURE_DEBUG=1`. They are
    /// always echoed so a redirected debug session still captures them.
    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        print(message)
    }

    private func echo(_ message: String) {
        guard Self.echoesToTerminal else { return }
        print(message)
    }
}
