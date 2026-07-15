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

    public var requiresFullRescan: Bool {
        events.contains(where: \ApplicationDirectoryEvent.requiresFullRescan)
    }

    public var containsRealChanges: Bool {
        events.contains { !$0.isHistoryDone }
    }

    public var requiresStreamRestart: Bool {
        events.contains {
            $0.flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
        }
    }
}

public enum ApplicationDirectoryMonitorError: LocalizedError {
    case noExistingRoots
    case cannotCreateStream
    case cannotStartStream

    public var errorDescription: String? {
        switch self {
        case .noExistingRoots:
            "没有可监听的应用目录"
        case .cannotCreateStream:
            "无法创建 FSEvents 监听流"
        case .cannotStartStream:
            "无法启动 FSEvents 监听流"
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

    public init(paths: [URL], latency: TimeInterval = 0.5) {
        self.paths = Array(Set(paths.map {
            $0.resolvingSymlinksInPath().standardizedFileURL.path
        })).sorted()
        self.latency = latency
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
        let events = (0..<eventCount).compactMap { index -> ApplicationDirectoryEvent? in
            guard let pathPointer = pathPointers[index] else { return nil }
            let path = String(cString: pathPointer)
            guard isRelevant(path) else { return nil }
            return ApplicationDirectoryEvent(
                path: path,
                eventID: ids[index],
                flags: flags[index]
            )
        }
        guard !events.isEmpty else { return }
        onEvents?(ApplicationDirectoryChangeBatch(events: events))
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

    private func isRelevant(_ eventPath: String) -> Bool {
        let normalizedEventPath = eventPath.hasSuffix("/") && eventPath.count > 1
            ? String(eventPath.dropLast())
            : eventPath
        return paths.contains { watchedPath in
            normalizedEventPath == watchedPath
                || normalizedEventPath.hasPrefix(watchedPath + "/")
                || watchedPath.hasPrefix(normalizedEventPath + "/")
        }
    }
}
