import ApplicationMonitorKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
let roots = arguments.isEmpty
    ? [
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true),
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
    ]
    : arguments.map { URL(fileURLWithPath: $0, isDirectory: true) }

let monitor = ApplicationDirectoryMonitor(paths: roots)
monitor.onEvents = { batch in
    let timestamp = ISO8601DateFormatter().string(from: Date())
    print("[\(timestamp)] events=\(batch.events.count) fullRescan=\(batch.requiresFullRescan)")
    for event in batch.events {
        print("  id=\(event.eventID) flags=\(event.flagNames.joined(separator: ",")) path=\(event.path)")
    }
    fflush(stdout)
}

do {
    try monitor.start()
    print("Monitoring:")
    roots.forEach { print("  \($0.path)") }
    fflush(stdout)
    RunLoop.main.run()
} catch {
    fputs("Failed to start monitoring: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
