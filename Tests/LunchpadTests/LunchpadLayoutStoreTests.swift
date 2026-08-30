import XCTest
@testable import Lunchpad

final class LunchpadLayoutStoreTests: XCTestCase {
    private var directory: URL!
    private var store: LunchpadLayoutStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LunchpadLayoutStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        store = try LunchpadLayoutStore(
            databaseURL: directory.appendingPathComponent("layout.sqlite3")
        )
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    private func app(_ name: String) -> AppItem {
        AppItem(
            identifier: "app.\(name.lowercased())",
            bundleIdentifier: "app.\(name.lowercased())",
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            creationDate: nil,
            modificationDate: nil
        )
    }

    private func reconcile(_ names: String...) throws -> [LunchpadItem] {
        try store.reconcile(names.map {
            DiscoveredApplication(item: app($0), shouldDefaultToOther: false)
        })
    }

    private func rootSlotNames(_ items: [LunchpadItem]) -> [String] {
        items.map(\.name)
    }

    private func folder(
        _ identifier: String,
        in items: [LunchpadItem]
    ) -> AppFolder? {
        items.compactMap { item -> AppFolder? in
            guard case .folder(let folder) = item else { return nil }
            return folder
        }.first { $0.identifier == identifier }
    }

    // MARK: Root rearrangement

    func testRootRearrangementReordersPersistedPositions() throws {
        _ = try reconcile("Alpha", "Bravo", "Charlie")

        try store.commit(.rootRearranged(slots: [
            .app(identifier: "app.charlie"),
            .app(identifier: "app.alpha"),
            .app(identifier: "app.bravo"),
        ]))

        XCTAssertEqual(rootSlotNames(try store.loadVisibleItems()), ["Charlie", "Alpha", "Bravo"])
    }

    func testRootRearrangementAcceptsUnchangedTrailingItems() throws {
        _ = try reconcile("Alpha", "Bravo", "Charlie", "Delta")

        // Moving two adjacent items leaves the trailing rows at their existing positions. Those
        // unchanged UPDATEs are still valid and must not be treated as a stale drag.
        try store.commit(.rootRearranged(slots: [
            .app(identifier: "app.bravo"),
            .app(identifier: "app.alpha"),
            .app(identifier: "app.charlie"),
            .app(identifier: "app.delta"),
        ]))

        XCTAssertEqual(
            rootSlotNames(try store.loadVisibleItems()),
            ["Bravo", "Alpha", "Charlie", "Delta"]
        )
    }

    func testRootRearrangementRejectsUnknownApplications() throws {
        _ = try reconcile("Alpha")

        XCTAssertThrowsError(try store.commit(.rootRearranged(slots: [
            .app(identifier: "app.missing"),
        ])))
        // The failed transaction must leave the stored arrangement untouched.
        XCTAssertEqual(rootSlotNames(try store.loadVisibleItems()), ["Alpha"])
    }

    func testRootRearrangementRejectsApplicationsThatBelongToFolders() throws {
        _ = try reconcile("Alpha", "Bravo")
        let folderIdentifier = try store.createFolder(name: "Games")
        try store.assignApplication(identifier: "app.alpha", toFolder: folderIdentifier)

        XCTAssertThrowsError(try store.commit(.rootRearranged(slots: [
            .app(identifier: "app.alpha"),
            .app(identifier: "app.bravo"),
        ])))
    }

    // MARK: Folder rearrangement

    func testFolderRearrangementReordersMembers() throws {
        _ = try reconcile("Chess", "Go", "Cards")
        let folderIdentifier = try store.createFolder(name: "Games")
        try store.assignApplication(identifier: "app.chess", toFolder: folderIdentifier)
        try store.assignApplication(identifier: "app.go", toFolder: folderIdentifier)
        try store.assignApplication(identifier: "app.cards", toFolder: folderIdentifier)

        try store.commit(.folderRearranged(
            folderIdentifier: folderIdentifier,
            appIdentifiers: ["app.cards", "app.chess", "app.go"],
            rootSlots: [.folder(identifier: folderIdentifier)]
        ))

        let items = try store.loadVisibleItems()
        XCTAssertEqual(folder(folderIdentifier, in: items)?.apps.map(\.name), ["Cards", "Chess", "Go"])
    }

    func testFolderRearrangementAcceptsUnchangedTrailingMembers() throws {
        _ = try reconcile("Chess", "Go", "Cards", "Solitaire")
        let folderIdentifier = try store.createFolder(name: "Games")
        for identifier in ["app.chess", "app.go", "app.cards", "app.solitaire"] {
            try store.assignApplication(identifier: identifier, toFolder: folderIdentifier)
        }

        try store.commit(.folderRearranged(
            folderIdentifier: folderIdentifier,
            appIdentifiers: ["app.go", "app.chess", "app.cards", "app.solitaire"],
            rootSlots: [.folder(identifier: folderIdentifier)]
        ))

        let items = try store.loadVisibleItems()
        XCTAssertEqual(
            folder(folderIdentifier, in: items)?.apps.map(\.name),
            ["Go", "Chess", "Cards", "Solitaire"]
        )
    }

    func testFolderRearrangementAppendsUnlistedMembers() throws {
        _ = try reconcile("Chess", "Go", "Cards")
        let folderIdentifier = try store.createFolder(name: "Games")
        for identifier in ["app.chess", "app.go", "app.cards"] {
            try store.assignApplication(identifier: identifier, toFolder: folderIdentifier)
        }

        try store.commit(.folderRearranged(
            folderIdentifier: folderIdentifier,
            appIdentifiers: ["app.go"],
            rootSlots: [.folder(identifier: folderIdentifier)]
        ))

        let items = try store.loadVisibleItems()
        XCTAssertEqual(folder(folderIdentifier, in: items)?.apps.map(\.name), ["Go", "Chess", "Cards"])
    }

    func testFirstFolderRearrangementAlsoPersistsPresentedRootOrder() throws {
        _ = try reconcile("Alpha", "Bravo", "Chess", "Go")
        let folderIdentifier = try store.createFolder(name: "Games")
        try store.assignApplication(identifier: "app.chess", toFolder: folderIdentifier)
        try store.assignApplication(identifier: "app.go", toFolder: folderIdentifier)

        try store.commit(.folderRearranged(
            folderIdentifier: folderIdentifier,
            appIdentifiers: ["app.go", "app.chess"],
            rootSlots: [
                .app(identifier: "app.alpha"),
                .app(identifier: "app.bravo"),
                .folder(identifier: folderIdentifier),
            ]
        ))

        let items = try store.loadVisibleItems()
        XCTAssertEqual(rootSlotNames(items), ["Alpha", "Bravo", "Games"])
        XCTAssertEqual(folder(folderIdentifier, in: items)?.apps.map(\.name), ["Go", "Chess"])
    }

    // MARK: Folder creation

    func testFolderCreationAssignsMembersAndOccupiesTheTargetSlot() throws {
        _ = try reconcile("Alpha", "Bravo", "Charlie", "Delta")

        try store.commit(.folderCreated(
            name: "New Folder",
            appIdentifiers: ["app.charlie", "app.alpha"],
            insertionIndex: 1,
            remainingRootSlots: [
                .app(identifier: "app.bravo"),
                .app(identifier: "app.delta"),
            ]
        ))

        let items = try store.loadVisibleItems()
        XCTAssertEqual(rootSlotNames(items), ["Bravo", "New Folder", "Delta"])

        let createdFolder = items.compactMap { item -> AppFolder? in
            guard case .folder(let folder) = item, folder.name == "New Folder" else { return nil }
            return folder
        }.first
        XCTAssertEqual(createdFolder?.apps.map(\.name), ["Charlie", "Alpha"])
    }

    func testFolderCreationSurvivesReconciliation() throws {
        _ = try reconcile("Alpha", "Bravo", "Charlie")
        try store.commit(.folderCreated(
            name: "New Folder",
            appIdentifiers: ["app.bravo", "app.alpha"],
            insertionIndex: 0,
            remainingRootSlots: [.app(identifier: "app.charlie")]
        ))

        let reconciled = try reconcile("Alpha", "Bravo", "Charlie")

        XCTAssertEqual(rootSlotNames(reconciled), ["New Folder", "Charlie"])
        let createdFolder = reconciled.compactMap { item -> AppFolder? in
            guard case .folder(let folder) = item else { return nil }
            return folder
        }.first
        XCTAssertEqual(createdFolder?.apps.map(\.name), ["Bravo", "Alpha"])
    }

    func testFolderCreationRejectsStaleApplicationsAtomically() throws {
        _ = try reconcile("Alpha")

        XCTAssertThrowsError(try store.commit(.folderCreated(
            name: "New Folder",
            appIdentifiers: ["app.alpha", "app.missing"],
            insertionIndex: 0,
            remainingRootSlots: [.app(identifier: "app.alpha")]
        )))

        XCTAssertEqual(rootSlotNames(try store.loadVisibleItems()), ["Alpha"])
    }

    // MARK: Folder membership changes

    func testAddingApplicationToFolderAppendsItAfterExistingMembers() throws {
        _ = try reconcile("Alpha", "Bravo", "Chess")
        let folderIdentifier = try store.createFolder(name: "Games")
        try store.assignApplication(identifier: "app.chess", toFolder: folderIdentifier)

        try store.commit(.appAddedToFolder(
            appIdentifier: "app.alpha",
            folderIdentifier: folderIdentifier,
            rootSlots: [
                .app(identifier: "app.bravo"),
                .folder(identifier: folderIdentifier),
            ]
        ))

        let items = try store.loadVisibleItems()
        XCTAssertEqual(folder(folderIdentifier, in: items)?.apps.map(\.name), ["Chess", "Alpha"])
        // The folder keeps its root slot; only the moved application's slot is vacated.
        XCTAssertEqual(rootSlotNames(items), ["Bravo", "Games"])
    }

    func testRemovingApplicationToRootPlacesItAfterTheFolder() throws {
        _ = try reconcile("Alpha", "Chess", "Go", "Bravo")
        let folderIdentifier = try store.createFolder(name: "Games")
        try store.assignApplication(identifier: "app.chess", toFolder: folderIdentifier)
        try store.assignApplication(identifier: "app.go", toFolder: folderIdentifier)

        // The root arrangement the drag UI supplies contains container items only; Go remains
        // inside the folder, so it never appears as its own root slot.
        try store.commit(.appRemovedToRoot(
            appIdentifier: "app.chess",
            sourceFolderIdentifier: folderIdentifier,
            rootSlots: [
                .app(identifier: "app.alpha"),
                .folder(identifier: folderIdentifier),
                .app(identifier: "app.chess"),
                .app(identifier: "app.bravo"),
            ]
        ))

        XCTAssertEqual(
            rootSlotNames(try store.loadVisibleItems()),
            ["Alpha", "Games", "Chess", "Bravo"]
        )
    }

    func testRemovingTheLastApplicationDeletesAnEmptyUserFolder() throws {
        _ = try reconcile("Alpha", "Chess")
        let folderIdentifier = try store.createFolder(name: "Games")
        try store.assignApplication(identifier: "app.chess", toFolder: folderIdentifier)

        try store.commit(.appRemovedToRoot(
            appIdentifier: "app.chess",
            sourceFolderIdentifier: folderIdentifier,
            rootSlots: [
                .app(identifier: "app.chess"),
                .app(identifier: "app.alpha"),
            ]
        ))

        let items = try store.loadVisibleItems()
        XCTAssertEqual(rootSlotNames(items), ["Chess", "Alpha"])
        XCTAssertNil(folder(folderIdentifier, in: items))
    }

    func testRemovingTheLastApplicationKeepsTheSystemFolder() throws {
        _ = try reconcile("Alpha", "Utility")
        try store.assignApplication(
            identifier: "app.utility",
            toFolder: LunchpadLayoutStore.otherFolderIdentifier
        )

        try store.commit(.appRemovedToRoot(
            appIdentifier: "app.utility",
            sourceFolderIdentifier: LunchpadLayoutStore.otherFolderIdentifier,
            rootSlots: [
                .app(identifier: "app.utility"),
                .app(identifier: "app.alpha"),
            ]
        ))

        let items = try store.loadVisibleItems()
        XCTAssertEqual(rootSlotNames(items), ["Utility", "Alpha"])
        // An empty system folder is omitted from the visible layout but must survive in the
        // database: assigning another application to Other only works while the row exists.
        try store.assignApplication(
            identifier: "app.alpha",
            toFolder: LunchpadLayoutStore.otherFolderIdentifier
        )
    }

    func testRemovingVisibleMemberPreservesUserFolderWithAbsentMember() throws {
        _ = try reconcile("Alpha", "Chess", "Go")
        let folderIdentifier = try store.createFolder(name: "Games")
        try store.assignApplication(identifier: "app.chess", toFolder: folderIdentifier)
        try store.assignApplication(identifier: "app.go", toFolder: folderIdentifier)

        // Go is temporarily absent, but its user assignment must survive moving the last visible
        // member out of the folder.
        _ = try reconcile("Alpha", "Chess")
        try store.commit(.appRemovedToRoot(
            appIdentifier: "app.chess",
            sourceFolderIdentifier: folderIdentifier,
            rootSlots: [
                .app(identifier: "app.alpha"),
                .folder(identifier: folderIdentifier),
                .app(identifier: "app.chess"),
            ]
        ))

        let reappeared = try reconcile("Alpha", "Chess", "Go")
        XCTAssertEqual(folder(folderIdentifier, in: reappeared)?.apps.map(\.name), ["Go"])
    }

    // MARK: Reconciliation interplay

    func testReconciliationPreservesDraggedPositionsAndAssignments() throws {
        _ = try reconcile("Alpha", "Bravo", "Charlie", "Zulu")
        try store.commit(.rootRearranged(slots: [
            .app(identifier: "app.zulu"),
            .app(identifier: "app.alpha"),
            .app(identifier: "app.charlie"),
            .app(identifier: "app.bravo"),
        ]))

        // A new application is discovered afterwards; it must append, not disturb the drag.
        let reconciled = try reconcile("Alpha", "Bravo", "Charlie", "Zulu", "NewApp")

        XCTAssertEqual(
            rootSlotNames(reconciled),
            ["Zulu", "Alpha", "Charlie", "Bravo", "NewApp"]
        )
    }

    func testReconciliationAppendsNewApplicationAfterTrailingFolder() throws {
        _ = try reconcile("Alpha", "Bravo", "Chess")
        let folderIdentifier = try store.createFolder(name: "Games")
        try store.assignApplication(identifier: "app.chess", toFolder: folderIdentifier)
        try store.commit(.rootRearranged(slots: [
            .app(identifier: "app.alpha"),
            .app(identifier: "app.bravo"),
            .folder(identifier: folderIdentifier),
        ]))

        let reconciled = try reconcile("Alpha", "Bravo", "Chess", "Delta")

        XCTAssertEqual(rootSlotNames(reconciled), ["Alpha", "Bravo", "Games", "Delta"])
    }

    func testUntouchedEmptyOtherFolderDoesNotCollideWithNewRootApplications() throws {
        _ = try reconcile("Alpha")
        try store.commit(.rootRearranged(slots: [
            .app(identifier: "app.alpha"),
        ]))

        _ = try reconcile("Alpha", "Bravo", "Utility")
        try store.assignApplication(
            identifier: "app.utility",
            toFolder: LunchpadLayoutStore.otherFolderIdentifier
        )

        XCTAssertEqual(
            rootSlotNames(try store.loadVisibleItems()),
            ["Alpha", "Bravo", "Other"]
        )
    }

    func testConcurrentReconciliationAndDragCommitsAreSerialized() async throws {
        let sharedStore = try XCTUnwrap(store)
        let discovered = (0..<64).map { index in
            DiscoveredApplication(item: app("App\(index)"), shouldDefaultToOther: false)
        }
        _ = try sharedStore.reconcile(discovered)

        let forwardSlots = (0..<64).map {
            LunchpadRootSlot.app(identifier: "app.app\($0)")
        }
        let reverseSlots = Array(forwardSlots.reversed())

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<24 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        _ = try sharedStore.reconcile(discovered)
                    } else {
                        try sharedStore.commit(.rootRearranged(
                            slots: index.isMultiple(of: 4)
                                ? forwardSlots
                                : reverseSlots
                        ))
                    }
                }
            }
            try await group.waitForAll()
        }

        XCTAssertEqual(try sharedStore.loadVisibleItems().flatMap(\.apps).count, 64)
    }

    func testStaleCatalogRefreshRebasesOntoLatestCommittedOrder() throws {
        let staleItems = try reconcile("Alpha", "Bravo", "Charlie")
        try store.commit(.rootRearranged(slots: [
            .app(identifier: "app.charlie"),
            .app(identifier: "app.alpha"),
            .app(identifier: "app.bravo"),
        ]))

        let rebased = try CatalogRefreshLayoutRebaser.rebase(
            scannedItems: staleItems,
            on: store
        )

        XCTAssertEqual(rootSlotNames(rebased), ["Charlie", "Alpha", "Bravo"])
    }

    func testDragCommitPositionsSurviveReopen() throws {
        _ = try reconcile("Alpha", "Bravo", "Charlie")
        try store.commit(.rootRearranged(slots: [
            .app(identifier: "app.bravo"),
            .app(identifier: "app.alpha"),
            .app(identifier: "app.charlie"),
        ]))

        let reopened = try LunchpadLayoutStore(
            databaseURL: directory.appendingPathComponent("layout.sqlite3")
        )
        XCTAssertEqual(rootSlotNames(try reopened.loadVisibleItems()), ["Bravo", "Alpha", "Charlie"])
    }
}
