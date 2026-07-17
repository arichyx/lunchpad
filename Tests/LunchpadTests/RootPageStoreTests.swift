import XCTest
@testable import Lunchpad

@MainActor
final class RootPageStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var now: Date!

    override func setUp() {
        super.setUp()
        suiteName = "LunchpadTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        now = nil
        super.tearDown()
    }

    private func makeStore() -> RootPageStore {
        RootPageStore(defaults: defaults, clock: { self.now })
    }

    func testRestoreWithinExpiryReturnsSavedPage() {
        let store = makeStore()
        store.save(page: 2)
        now = now.addingTimeInterval(10) // 10s < 30s
        XCTAssertEqual(store.restoredPage(availablePageCount: 5), 2)
    }

    func testRestoreAfterExpiryReturnsZero() {
        let store = makeStore()
        store.save(page: 2)
        now = now.addingTimeInterval(31) // > 30s
        XCTAssertEqual(store.restoredPage(availablePageCount: 5), 0)
    }

    func testClampWhenSavedPageExceedsPageCount() {
        let store = makeStore()
        store.save(page: 4) // fresh (no time advance)
        XCTAssertEqual(store.restoredPage(availablePageCount: 2), 1) // min(4, 2-1) = 1
    }

    func testMissingSavedPageReturnsZero() {
        let store = makeStore()
        // Nothing saved.
        XCTAssertEqual(store.restoredPage(availablePageCount: 5), 0)
    }

    func testMissingTimestampReturnsZero() {
        let store = makeStore()
        store.save(page: 2)
        defaults.removeObject(forKey: "rootPageSavedAt")
        // A page of unknown age is never restored.
        XCTAssertEqual(store.restoredPage(availablePageCount: 5), 0)
    }

    func testNegativeSavedPageReturnsZero() {
        let store = makeStore()
        store.save(page: 2)
        defaults.set(-3, forKey: "rootPageIndex") // simulate external tampering
        XCTAssertEqual(store.restoredPage(availablePageCount: 5), 0)
    }

    func testFutureDatedSaveTimeReturnsZero() {
        let store = makeStore()
        store.save(page: 2)
        now = now.addingTimeInterval(-100) // clock moved back; savedAt is now in the future
        XCTAssertEqual(store.restoredPage(availablePageCount: 5), 0)
    }

    func testZeroPageCountReturnsZero() {
        let store = makeStore()
        store.save(page: 2) // fresh
        XCTAssertEqual(store.restoredPage(availablePageCount: 0), 0)
    }

    func testSavedPageZeroIsRestored() {
        let store = makeStore()
        store.save(page: 0)
        XCTAssertEqual(store.restoredPage(availablePageCount: 5), 0)
        // The timestamp must still be present and fresh for this to be a real save, not a missing one.
        XCTAssertNotNil(defaults.object(forKey: "rootPageSavedAt"))
    }
}

final class RootPageSelectionTests: XCTestCase {
    func testFolderOpenReturnsRootPageBeforeEnteringFolder() {
        XCTAssertEqual(
            RootPageSelection.rootPageToSave(
                folderOpen: true,
                searchActive: false,
                currentPage: 1,
                rootPageBeforeEnteringFolder: 3
            ),
            3
        )
    }

    func testSearchActiveReturnsZeroRegardlessOfCurrentPage() {
        XCTAssertEqual(
            RootPageSelection.rootPageToSave(
                folderOpen: false,
                searchActive: true,
                currentPage: 2,
                rootPageBeforeEnteringFolder: 0
            ),
            0
        )
    }

    func testDefaultReturnsCurrentPage() {
        XCTAssertEqual(
            RootPageSelection.rootPageToSave(
                folderOpen: false,
                searchActive: false,
                currentPage: 4,
                rootPageBeforeEnteringFolder: 0
            ),
            4
        )
    }

    func testFolderOpenTakesPrecedenceOverSearch() {
        // Inside a folder the search field is cleared, so this state is unreachable in practice;
        // the function still picks the folder branch deterministically.
        XCTAssertEqual(
            RootPageSelection.rootPageToSave(
                folderOpen: true,
                searchActive: true,
                currentPage: 1,
                rootPageBeforeEnteringFolder: 3
            ),
            3
        )
    }

    func testNegativeInputsAreClampedToZero() {
        XCTAssertEqual(
            RootPageSelection.rootPageToSave(
                folderOpen: false,
                searchActive: false,
                currentPage: -1,
                rootPageBeforeEnteringFolder: -2
            ),
            0
        )
    }
}
