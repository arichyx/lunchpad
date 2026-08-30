import SQLite3
import XCTest
@testable import Lunchpad

final class ApplicationCatalogSynchronizerTests: XCTestCase {
    func testInitialReconciliationFailureReportsFlatLayoutFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ApplicationCatalogSynchronizerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("layout.sqlite3")
        let store = try LunchpadLayoutStore(databaseURL: databaseURL)

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(
            sqlite3_exec(database, "DROP TABLE applications", nil, nil, nil),
            SQLITE_OK
        )

        let synchronizer = ApplicationCatalogSynchronizer(
            scanner: AppScanner(roots: [directory.appendingPathComponent("Applications")]),
            layoutStore: store,
            quietDelay: 0,
            stabilityDelay: 0
        )

        let initialCatalog = synchronizer.loadInitialCatalog()

        XCTAssertFalse(initialCatalog.usesPersistentLayout)
        XCTAssertTrue(initialCatalog.items.isEmpty)
        XCTAssertFalse(synchronizer.loadInitialCatalog().usesPersistentLayout)
    }
}
