import CoreServices
import XCTest
@testable import ApplicationMonitorKit

final class ApplicationDirectoryMonitorTests: XCTestCase {
    func testDroppedEventsRequireRecoveryScan() {
        let event = makeEvent(
            flags: FSEventStreamEventFlags(
                kFSEventStreamEventFlagMustScanSubDirs
                    | kFSEventStreamEventFlagKernelDropped
            )
        )
        let batch = ApplicationDirectoryChangeBatch(events: [event])

        XCTAssertTrue(event.requiresFullRescan)
        XCTAssertTrue(batch.requiresFullRescan)
        XCTAssertFalse(batch.requiresStreamRestart)
        XCTAssertTrue(event.flagNames.contains("kernel-dropped"))
    }

    func testRootChangeRequiresStreamRestart() {
        let event = makeEvent(
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
        )
        let batch = ApplicationDirectoryChangeBatch(events: [event])

        XCTAssertTrue(batch.requiresFullRescan)
        XCTAssertTrue(batch.requiresStreamRestart)
    }

    func testHistoryDoneIsNotTreatedAsDirectoryChange() {
        let event = makeEvent(
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)
        )
        let batch = ApplicationDirectoryChangeBatch(events: [event])

        XCTAssertTrue(event.isHistoryDone)
        XCTAssertFalse(batch.containsRealChanges)
        XCTAssertFalse(batch.requiresFullRescan)
    }

    func testUnrelatedWriteInAncestorOfMissingRootIsIgnored() {
        var filter = ApplicationDirectoryEventFilter(
            watchedPaths: ["/Users/person/Applications"],
            directoryExists: { _ in false }
        )

        XCTAssertEqual(
            filter.relevance(ofEventPath: "/Users/person/", flags: 0),
            .irrelevant
        )
        XCTAssertEqual(
            filter.relevance(ofEventPath: "/Users/person/Library/Caches/", flags: 0),
            .irrelevant
        )
    }

    func testAncestorEventReportsRootAvailabilityChangeOnce() {
        var rootExists = false
        var filter = ApplicationDirectoryEventFilter(
            watchedPaths: ["/Users/person/Applications"],
            directoryExists: { _ in rootExists }
        )

        rootExists = true
        XCTAssertEqual(
            filter.relevance(ofEventPath: "/Users/person/", flags: 0),
            .rootAvailabilityChanged
        )
        XCTAssertEqual(
            filter.relevance(ofEventPath: "/Users/person/", flags: 0),
            .irrelevant
        )

        rootExists = false
        XCTAssertEqual(
            filter.relevance(ofEventPath: "/Users/person", flags: 0),
            .rootAvailabilityChanged
        )
    }

    func testRecoveryEventOnAncestorRemainsRelevant() {
        var filter = ApplicationDirectoryEventFilter(
            watchedPaths: ["/Users/person/Applications"],
            directoryExists: { _ in false }
        )

        XCTAssertEqual(
            filter.relevance(
                ofEventPath: "/Users/person/",
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
            ),
            .relevant
        )
    }

    func testEventsInsideWatchedRootAreRelevant() {
        var filter = ApplicationDirectoryEventFilter(
            watchedPaths: ["/Applications"],
            directoryExists: { _ in true }
        )

        XCTAssertEqual(filter.relevance(ofEventPath: "/Applications/", flags: 0), .relevant)
        XCTAssertEqual(
            filter.relevance(ofEventPath: "/Applications/Safari.app/Contents/", flags: 0),
            .relevant
        )
        XCTAssertEqual(
            filter.relevance(ofEventPath: "/ApplicationsBackup/", flags: 0),
            .irrelevant
        )
        XCTAssertEqual(filter.relevance(ofEventPath: "/", flags: 0), .irrelevant)
    }

    func testRootAvailabilityChangeRequiresRestartAndRescan() {
        let batch = ApplicationDirectoryChangeBatch(
            events: [makeEvent(flags: 0)],
            rootAvailabilityChanged: true
        )

        XCTAssertTrue(batch.containsRealChanges)
        XCTAssertTrue(batch.requiresFullRescan)
        XCTAssertTrue(batch.requiresStreamRestart)
    }

    /// A missing root is watched through its parent. Writes next to the root must not produce
    /// batches, while creating the root must.
    func testMonitorIgnoresSiblingWritesUntilMissingRootAppears() throws {
        let base = try makeCanonicalTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("Applications", isDirectory: true)

        let monitor = ApplicationDirectoryMonitor(paths: [root], latency: 0.1)
        let batches = BatchRecorder()
        monitor.onEvents = { batches.append($0) }
        try monitor.start()
        defer { monitor.stop() }

        try Data("history".utf8).write(to: base.appendingPathComponent(".zsh_history"))
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(batches.snapshot.isEmpty)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let deadline = Date().addingTimeInterval(5)
        while batches.snapshot.isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(batches.snapshot.first?.rootAvailabilityChanged, true)
    }

    private func makeCanonicalTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ApplicationDirectoryMonitorTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // FSEvents reports canonical paths such as /private/var/...; match them exactly.
        guard let canonicalPath = realpath(directory.path, nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { free(canonicalPath) }
        return URL(fileURLWithPath: String(cString: canonicalPath), isDirectory: true)
    }

    private func makeEvent(
        flags: FSEventStreamEventFlags
    ) -> ApplicationDirectoryEvent {
        ApplicationDirectoryEvent(
            path: "/Applications",
            eventID: 1,
            flags: flags
        )
    }
}

private final class BatchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [ApplicationDirectoryChangeBatch] = []

    func append(_ batch: ApplicationDirectoryChangeBatch) {
        lock.lock()
        batches.append(batch)
        lock.unlock()
    }

    var snapshot: [ApplicationDirectoryChangeBatch] {
        lock.lock()
        defer { lock.unlock() }
        return batches
    }
}
