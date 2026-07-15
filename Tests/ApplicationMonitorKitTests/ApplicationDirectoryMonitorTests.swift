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
