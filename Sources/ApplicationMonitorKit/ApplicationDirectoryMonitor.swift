import CoreServices
import Foundation

/// FSEvents only indicates that an application directory may have changed.
public struct ApplicationDirectoryEvent: Sendable {
    public let path: String
    public let eventID: FSEventStreamEventId
    public let flags: FSEventStreamEventFlags

    public var requiresFullRescan: Bool {
        let recoveryFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagEventIdsWrapped
                | kFSEventStreamEventFlagRootChanged
        )
        return flags & recoveryFlags != 0
    }

    public var isHistoryDone: Bool {
        flags & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) != 0
    }

    public var flagNames: [String] {
        let knownFlags: [(FSEventStreamEventFlags, String)] = [
            (FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs), "must-scan-subdirs"),
            (FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped), "user-dropped"),
            (FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped), "kernel-dropped"),
            (FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped), "ids-wrapped"),
            (FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone), "history-done"),
            (FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged), "root-changed"),
            (FSEventStreamEventFlags(kFSEventStreamEventFlagMount), "mount"),
            (FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount), "unmount"),
        ]
        let names = knownFlags.compactMap { flag, name in
            flags & flag != 0 ? name : nil
        }
        return names.isEmpty ? ["none"] : names
    }
}

public struct ApplicationDirectoryChangeBatch: Sendable {
    public let events: [ApplicationDirectoryEvent]
    /// A watched root that is observed through an ancestor directory appeared or disappeared.
    /// The stream must be rebuilt so it watches the nearest existing directory again.
    public let rootAvailabilityChanged: Bool

    public init(events: [ApplicationDirectoryEvent], rootAvailabilityChanged: Bool = false) {
        self.events = events
        self.rootAvailabilityChanged = rootAvailabilityChanged
    }

    public var requiresFullRescan: Bool {
        rootAvailabilityChanged
            || events.contains(where: \ApplicationDirectoryEvent.requiresFullRescan)
    }

    public var containsRealChanges: Bool {
        rootAvailabilityChanged || events.contains { !$0.isHistoryDone }
    }

    public var requiresStreamRestart: Bool {
        rootAvailabilityChanged || events.contains {
            $0.flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
        }
    }
}

/// Decides which FSEvents paths concern the watched application roots.
///
/// A missing root is watched through its nearest existing ancestor, which also reports unrelated
/// writes such as shell history files in the home directory. An event on such an ancestor matters
/// only when a watched root appeared or disappeared, or when FSEvents requests a recovery scan.
struct ApplicationDirectoryEventFilter {
    enum Relevance: Equatable {
        case irrelevant
        case relevant
        case rootAvailabilityChanged
    }

    let watchedPaths: [String]
    private let directoryExists: (String) -> Bool
    private var knownAvailability: [String: Bool] = [:]

    init(watchedPaths: [String], directoryExists: @escaping (String) -> Bool) {
        self.watchedPaths = watchedPaths
        self.directoryExists = directoryExists
        refreshAvailability()
    }

    /// Records whether each watched root currently exists. Called whenever the stream is rebuilt.
    mutating func refreshAvailability() {
        for path in watchedPaths {
            knownAvailability[path] = directoryExists(path)
        }
    }

    mutating func relevance(
        ofEventPath eventPath: String,
        flags: FSEventStreamEventFlags
    ) -> Relevance {
        let normalizedEventPath = eventPath.hasSuffix("/") && eventPath.count > 1
            ? String(eventPath.dropLast())
            : eventPath
        let ancestorPrefix = normalizedEventPath == "/" ? "/" : normalizedEventPath + "/"
        let requiresRecovery = ApplicationDirectoryEvent(
            path: eventPath,
            eventID: 0,
            flags: flags
        ).requiresFullRescan

        var result = Relevance.irrelevant
        for watchedPath in watchedPaths {
            if normalizedEventPath == watchedPath
                || normalizedEventPath.hasPrefix(watchedPath + "/") {
                if result == .irrelevant { result = .relevant }
                continue
            }
            guard watchedPath.hasPrefix(ancestorPrefix) else { continue }

            let exists = directoryExists(watchedPath)
            if knownAvailability[watchedPath] != exists {
                knownAvailability[watchedPath] = exists
                result = .rootAvailabilityChanged
            } else if requiresRecovery, result == .irrelevant {
                result = .relevant
            }
        }
        return result
    }
}

public enum ApplicationDirectoryMonitorError: LocalizedError {
    case noExistingRoots
    case cannotCreateStream
    case cannotStartStream

    public var errorDescription: String? {
        switch self {
        case .noExistingRoots:
            "No application directories available to monitor"
        case .cannotCreateStream:
            "Unable to create FSEvents monitor stream"
        case .cannotStartStream:
            "Unable to start FSEvents monitor stream"
        }
    }
}

/// Directory-level FSEvents monitor. FileEvents is intentionally disabled so writes inside
/// an app bundle do not become individual application-level events.
public final class ApplicationDirectoryMonitor: @unchecked Sendable {
    public var onEvents: (@Sendable (ApplicationDirectoryChangeBatch) -> Void)?

    private let paths: [String]
    private let latency: CFTimeInterval
    private let callbackQueue = DispatchQueue(
        label: "com.arichyx.lunchpad.application-directory-monitor",
        qos: .utility
    )
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    /// Guards `eventFilter`. Never held while calling FSEvents, so a callback cannot deadlock
    /// against `stop()`.
    private let filterLock = NSLock()
    private var eventFilter: ApplicationDirectoryEventFilter

    public init(paths: [URL], latency: TimeInterval = 0.5) {
        let paths = Array(Set(paths.map {
            $0.resolvingSymlinksInPath().standardizedFileURL.path
        })).sorted()
        self.paths = paths
        self.latency = latency
        eventFilter = ApplicationDirectoryEventFilter(watchedPaths: paths) { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil else { return }

        // ~/Applications may not exist at startup. Watch the nearest existing parent and
        // retain only events related to the requested target path.
        let existingPaths = Array(Set(paths.compactMap(nearestExistingDirectory))).sorted()
        guard !existingPaths.isEmpty else {
            throw ApplicationDirectoryMonitorError.noExistingRoots
        }
        filterLock.lock()
        eventFilter.refreshAvailability()
        filterLock.unlock()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = {
            _, callbackInfo, eventCount, rawPaths, eventFlags, eventIDs in
            guard let callbackInfo else { return }
            let monitor = Unmanaged<ApplicationDirectoryMonitor>
                .fromOpaque(callbackInfo)
                .takeUnretainedValue()
            monitor.receive(
                eventCount: eventCount,
                rawPaths: rawPaths,
                flags: eventFlags,
                ids: eventIDs
            )
        }

        guard let createdStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            existingPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
        ) else {
            throw ApplicationDirectoryMonitorError.cannotCreateStream
        }

        FSEventStreamSetDispatchQueue(createdStream, callbackQueue)
        guard FSEventStreamStart(createdStream) else {
            FSEventStreamInvalidate(createdStream)
            throw ApplicationDirectoryMonitorError.cannotStartStream
        }
        stream = createdStream
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
    }

    private func receive(
        eventCount: Int,
        rawPaths: UnsafeMutableRawPointer,
        flags: UnsafePointer<FSEventStreamEventFlags>,
        ids: UnsafePointer<FSEventStreamEventId>
    ) {
        guard eventCount > 0 else { return }
        let pathPointers = rawPaths.bindMemory(
            to: UnsafePointer<CChar>?.self,
            capacity: eventCount
        )
        var rootAvailabilityChanged = false
        filterLock.lock()
        let events = (0..<eventCount).compactMap { index -> ApplicationDirectoryEvent? in
            guard let pathPointer = pathPointers[index] else { return nil }
            let path = String(cString: pathPointer)
            switch eventFilter.relevance(ofEventPath: path, flags: flags[index]) {
            case .irrelevant:
                return nil
            case .rootAvailabilityChanged:
                rootAvailabilityChanged = true
            case .relevant:
                break
            }
            return ApplicationDirectoryEvent(
                path: path,
                eventID: ids[index],
                flags: flags[index]
            )
        }
        filterLock.unlock()
        guard !events.isEmpty else { return }
        onEvents?(ApplicationDirectoryChangeBatch(
            events: events,
            rootAvailabilityChanged: rootAvailabilityChanged
        ))
    }

    private func nearestExistingDirectory(for path: String) -> String? {
        var url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false

        while !FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) || !isDirectory.boolValue {
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else { return nil }
            url = parent
            isDirectory = false
        }
        return url.path
    }

}
