import XCTest
@testable import Lunchpad

final class GridDragArrangementTests: XCTestCase {
    // MARK: DragSplice

    func testSpliceMovingForwardShiftsFinalIndex() {
        XCTAssertEqual(DragSplice.finalIndex(from: 0, rawInsertion: 2, count: 4), 1)
        XCTAssertEqual(DragSplice.finalIndex(from: 0, rawInsertion: 4, count: 4), 3)
    }

    func testSpliceMovingBackwardKeepsRawIndex() {
        XCTAssertEqual(DragSplice.finalIndex(from: 3, rawInsertion: 1, count: 4), 1)
        XCTAssertEqual(DragSplice.finalIndex(from: 3, rawInsertion: 0, count: 4), 0)
    }

    func testSpliceRejectsNoOpMoves() {
        XCTAssertNil(DragSplice.finalIndex(from: 1, rawInsertion: 1, count: 4))
        XCTAssertNil(DragSplice.finalIndex(from: 1, rawInsertion: 2, count: 4))
        XCTAssertNil(DragSplice.finalIndex(from: 1, rawInsertion: 2, count: 1))
    }

    func testSpliceClampsOutOfBoundsInsertions() {
        XCTAssertEqual(DragSplice.finalIndex(from: 2, rawInsertion: -5, count: 4), 0)
        XCTAssertEqual(DragSplice.finalIndex(from: 2, rawInsertion: 99, count: 4), 3)
    }

    // MARK: GridDropLocator

    private let slotSize = NSSize(width: 100, height: 100)

    private func frames(count: Int, spacing: CGFloat = 100) -> [NSRect] {
        (0..<count).map { index in
            NSRect(
                x: CGFloat(index % 7) * spacing,
                y: CGFloat(index / 7) * spacing,
                width: slotSize.width,
                height: slotSize.height
            )
        }
    }

    /// Identity occupants: cell i displays item i for the first itemCount cells.
    private func occupants(itemCount: Int, capacity: Int = 35) -> [Int] {
        (0..<capacity).map { $0 < itemCount ? $0 : -1 }
    }

    /// Merge hit areas: a 72-point square centered in each 100-point cell.
    private func iconAreas(from cells: [NSRect]) -> [NSRect] {
        cells.map { $0.insetBy(dx: 14, dy: 14) }
    }

    func testLocatorPrefersItemHitsOverNearestSlot() {
        XCTAssertEqual(
            GridDropLocator.candidate(
                point: NSPoint(x: 150, y: 50),
                draggedSlotIndex: nil,
                cellOccupants: occupants(itemCount: 3),
                cellFrames: frames(count: 35),
                iconFrames: iconAreas(from: frames(count: 35)),
                removalTargetFrame: nil
            ),
            .item(pageLocalSlot: 1)
        )
    }

    func testLocatorTargetsTheShiftedIconNotTheVacatedCell() {
        // Mapping [1, 0, 2]: item 1 now displays in cell 0. Hovering cell 0 targets item 1.
        let mapping = [1, 0, 2] + Array(repeating: -1, count: 32)
        XCTAssertEqual(
            GridDropLocator.candidate(
                point: NSPoint(x: 50, y: 50),
                draggedSlotIndex: 0,
                cellOccupants: mapping,
                cellFrames: frames(count: 35),
                iconFrames: iconAreas(from: frames(count: 35)),
                removalTargetFrame: nil
            ),
            .item(pageLocalSlot: 1)
        )
    }

    func testLocatorTreatsTheOpenGapAsInsertion() {
        // Mapping [1, 0, 2]: cell 1 holds the dragged item's gap. Hovering it inserts there.
        let mapping = [1, 0, 2] + Array(repeating: -1, count: 32)
        let candidate = GridDropLocator.candidate(
            point: NSPoint(x: 150, y: 50),
            draggedSlotIndex: 0,
            cellOccupants: mapping,
            cellFrames: frames(count: 35),
            iconFrames: iconAreas(from: frames(count: 35)),
            removalTargetFrame: nil
        )
        XCTAssertEqual(candidate, .insertionSlot(slotIndex: 1))
    }

    func testLocatorIgnoresTheDraggedItemFrame() {
        let candidate = GridDropLocator.candidate(
            point: NSPoint(x: 50, y: 50),
            draggedSlotIndex: 0,
            cellOccupants: occupants(itemCount: 3),
            cellFrames: frames(count: 35),
            iconFrames: iconAreas(from: frames(count: 35)),
            removalTargetFrame: nil
        )
        // The pointer sits inside cell 0, but that is the dragged item: nearest-cell insertion.
        XCTAssertEqual(candidate, .insertionSlot(slotIndex: 0))
    }

    func testForwardDragInsertsBeforeTheIconWhenHoveringItsLeftBorderArea() {
        // Cell 1 spans x 100-200; its merge area is x 114-186. Dragging forward (slot 0) and
        // hovering x 105 snaps to the boundary before item 1 so item 1 stays put.
        let candidate = GridDropLocator.candidate(
            point: NSPoint(x: 105, y: 50),
            draggedSlotIndex: 0,
            cellOccupants: occupants(itemCount: 3),
            cellFrames: frames(count: 35),
            iconFrames: iconAreas(from: frames(count: 35)),
            removalTargetFrame: nil
        )
        XCTAssertEqual(candidate, .insertionSlot(slotIndex: 0))
    }

    func testForwardDragInsertsAtTheHoveredCellWhenRightOfItsCenter() {
        // x 195 lies right of cell 1's center (150) and outside its artwork (114-186).
        let candidate = GridDropLocator.candidate(
            point: NSPoint(x: 195, y: 50),
            draggedSlotIndex: 0,
            cellOccupants: occupants(itemCount: 3),
            cellFrames: frames(count: 35),
            iconFrames: iconAreas(from: frames(count: 35)),
            removalTargetFrame: nil
        )
        XCTAssertEqual(candidate, .insertionSlot(slotIndex: 1))
    }

    func testBackwardDragInsertsAfterTheIconWhenHoveringItsRightBorderArea() {
        // Dragging backward (slot 5) toward cell 1 and hovering its right border area opens
        // the gap after item 1 so item 1 does not slide right, out from under the pointer.
        let candidate = GridDropLocator.candidate(
            point: NSPoint(x: 195, y: 50),
            draggedSlotIndex: 5,
            cellOccupants: occupants(itemCount: 3),
            cellFrames: frames(count: 35),
            iconFrames: iconAreas(from: frames(count: 35)),
            removalTargetFrame: nil
        )
        XCTAssertEqual(candidate, .insertionSlot(slotIndex: 2))
    }

    func testBackwardDragInsertsAtTheHoveredCellWhenLeftOfItsCenter() {
        let candidate = GridDropLocator.candidate(
            point: NSPoint(x: 105, y: 50),
            draggedSlotIndex: 5,
            cellOccupants: occupants(itemCount: 3),
            cellFrames: frames(count: 35),
            iconFrames: iconAreas(from: frames(count: 35)),
            removalTargetFrame: nil
        )
        XCTAssertEqual(candidate, .insertionSlot(slotIndex: 1))
    }

    func testLocatorDetectsRemovalTarget() {
        let candidate = GridDropLocator.candidate(
            point: NSPoint(x: 300, y: 500),
            draggedSlotIndex: 0,
            cellOccupants: occupants(itemCount: 3),
            cellFrames: frames(count: 35),
            iconFrames: iconAreas(from: frames(count: 35)),
            removalTargetFrame: NSRect(x: 250, y: 480, width: 100, height: 40)
        )
        XCTAssertEqual(candidate, .removalTarget)
    }

    func testLocatorFindsNearestSlotForGapDrops() {
        // Slots are 100 wide but spaced 150 apart; 260 lies in the gap after slot 1, nearer to
        // slot 1's side. A backward drag (slot 5) snaps after slot 1 so its icon stays put,
        // which lands the gap just right of item 1 — the side the pointer hugs.
        let candidate = GridDropLocator.candidate(
            point: NSPoint(x: 260, y: 50),
            draggedSlotIndex: 5,
            cellOccupants: occupants(itemCount: 3),
            cellFrames: frames(count: 35, spacing: 150),
            iconFrames: iconAreas(from: frames(count: 35, spacing: 150)),
            removalTargetFrame: nil
        )
        XCTAssertEqual(candidate, .insertionSlot(slotIndex: 2))

        // The same gap hovered by a forward drag snaps before the neighbor instead.
        let forward = GridDropLocator.candidate(
            point: NSPoint(x: 260, y: 50),
            draggedSlotIndex: 0,
            cellOccupants: occupants(itemCount: 3),
            cellFrames: frames(count: 35, spacing: 150),
            iconFrames: iconAreas(from: frames(count: 35, spacing: 150)),
            removalTargetFrame: nil
        )
        XCTAssertEqual(forward, .insertionSlot(slotIndex: 1))
    }

    // MARK: DragPreview

    func testPreviewForwardLandsAtTheHoveredCell() {
        // Drag slot 0 to cell 2: the icon lands in cell 2, so items 1 and 2 shift left and the
        // gap opens at cell 2 itself — the ghost and the commit both use that cell.
        XCTAssertEqual(
            DragPreview.previewSlots(draggedSlot: 0, targetSlot: 2, itemCount: 4),
            [2, 0, 1, 3]
        )
    }

    func testPreviewOpeningGapBackwardShiftsItemsRight() {
        // Drag slot 3 into the gap before slot 1: slots 1 and 2 shift right, gap at position 1.
        XCTAssertEqual(
            DragPreview.previewSlots(draggedSlot: 3, targetSlot: 1, itemCount: 4),
            [0, 2, 3, 1]
        )
    }

    func testPreviewAppendingAfterTheLastItemKeepsOthersInPlace() {
        XCTAssertEqual(
            DragPreview.previewSlots(draggedSlot: 1, targetSlot: 4, itemCount: 3),
            [0, 2, 1]
        )
    }

    func testPreviewReturnsNilForNoOpAndTrivialInputs() {
        XCTAssertNil(DragPreview.previewSlots(draggedSlot: 1, targetSlot: 1, itemCount: 4))
        XCTAssertNil(DragPreview.previewSlots(draggedSlot: 0, targetSlot: 1, itemCount: 1))
        // Landing one cell right of the origin is a real move now, not a no-op.
        XCTAssertEqual(
            DragPreview.previewSlots(draggedSlot: 1, targetSlot: 2, itemCount: 4),
            [0, 2, 1, 3]
        )
    }

    // MARK: Cross-page preview

    func testCrossPageForwardTurnVacatesTheLandingCell() {
        // Forward: slots up to and including the landing slot compact left; slot 0 spills to
        // the previous page; the landing cell itself is left free for the dragged item.
        XCTAssertEqual(
            DragPreview.crossPageSlots(landingSlot: 2, itemCount: 5, forward: true),
            [-1, 0, 1, 3, 4]
        )
    }

    func testCrossPageBackwardTurnVacatesTheLandingCell() {
        // Slot 4 maps to 5 as a next-page overflow sentinel when this is a full page.
        XCTAssertEqual(
            DragPreview.crossPageSlots(landingSlot: 2, itemCount: 5, forward: false),
            [0, 1, 3, 4, 5]
        )
    }

    func testCrossPageForwardLandingAtZeroFreesTheFirstCell() {
        XCTAssertEqual(
            DragPreview.crossPageSlots(landingSlot: 0, itemCount: 3, forward: true),
            [-1, 1, 2]
        )
    }

    func testCrossPagePreviewClampsLandingToTheLastOccupiedCell() {
        XCTAssertEqual(
            DragPreview.crossPageSlots(landingSlot: 99, itemCount: 3, forward: true),
            [-1, 0, 1]
        )
        XCTAssertEqual(
            DragPreview.crossPageSlots(landingSlot: -99, itemCount: 3, forward: false),
            [1, 2, 3]
        )
        XCTAssertTrue(DragPreview.crossPageSlots(landingSlot: 0, itemCount: 0, forward: true).isEmpty)
    }

    // MARK: DragPageEdgePolicy

    func testEdgePolicyWaitsUntilDwellElapses() {
        XCTAssertEqual(
            DragPageEdgePolicy.decide(
                edgeDelta: 1,
                inEdgeDuration: 0.39,
                dwell: 0.4,
                sinceLastTurn: 10,
                cooldown: 1.1,
                targetPage: 1,
                pageCount: 3
            ),
            .wait
        )
        XCTAssertEqual(
            DragPageEdgePolicy.decide(
                edgeDelta: -1,
                inEdgeDuration: 0.4,
                dwell: 0.4,
                sinceLastTurn: 10,
                cooldown: 1.1,
                targetPage: 1,
                pageCount: 3
            ),
            .turn(delta: -1)
        )
    }

    func testEdgePolicyWaitsThroughTheCooldownAfterATurn() {
        XCTAssertEqual(
            DragPageEdgePolicy.decide(
                edgeDelta: 1,
                inEdgeDuration: 5,
                dwell: 0.4,
                sinceLastTurn: 1.0,
                cooldown: 1.1,
                targetPage: 2,
                pageCount: 3
            ),
            .wait
        )
    }

    func testEdgePolicyIgnoresOutsideTheStripAndMissingPages() {
        XCTAssertEqual(
            DragPageEdgePolicy.decide(
                edgeDelta: nil,
                inEdgeDuration: 5,
                dwell: 0.4,
                sinceLastTurn: 10,
                cooldown: 1.1,
                targetPage: 1,
                pageCount: 3
            ),
            .none
        )
        // On the last page, no further turn exists in that direction.
        XCTAssertEqual(
            DragPageEdgePolicy.decide(
                edgeDelta: 1,
                inEdgeDuration: 5,
                dwell: 0.4,
                sinceLastTurn: 10,
                cooldown: 1.1,
                targetPage: 3,
                pageCount: 3
            ),
            .none
        )
    }

    // MARK: DragMergeStickiness

    private let stickinessFrames = (0..<4).map {
        NSRect(x: CGFloat($0) * 100, y: 0, width: 100, height: 100)
    }

    func testStickyMergeHoldsWhileThePointerStaysInTheTargetsCell() {
        // The artwork of slot 2 was hovered (sticky set); the pointer drifts into the cell's
        // margin where the raw candidate is an insertion.
        let result = DragMergeStickiness.resolve(
            raw: .insertionSlot(slotIndex: 2),
            stickySlot: 2,
            point: NSPoint(x: 205, y: 90),
            cellFrames: stickinessFrames,
            itemCount: 4,
            visualCellForSlot: { $0 }
        )
        XCTAssertEqual(result.candidate, .item(pageLocalSlot: 2))
        XCTAssertEqual(result.stickySlot, 2)
    }

    func testStickyMergeTracksTheTargetsShiftedCell() {
        // Slot 2 is displayed one cell left (mapping 2->1); the sticky region follows it.
        let result = DragMergeStickiness.resolve(
            raw: .insertionSlot(slotIndex: 3),
            stickySlot: 2,
            point: NSPoint(x: 150, y: 50),
            cellFrames: stickinessFrames,
            itemCount: 4,
            visualCellForSlot: { slot in slot == 2 ? 1 : slot }
        )
        XCTAssertEqual(result.candidate, .item(pageLocalSlot: 2))
    }

    func testStickyMergeClearsOnceThePointerLeavesTheCell() {
        let result = DragMergeStickiness.resolve(
            raw: .insertionSlot(slotIndex: 3),
            stickySlot: 2,
            point: NSPoint(x: 350, y: 50),
            cellFrames: stickinessFrames,
            itemCount: 4,
            visualCellForSlot: { $0 }
        )
        XCTAssertEqual(result.candidate, .insertionSlot(slotIndex: 3))
        XCTAssertNil(result.stickySlot)
    }

    func testStickyMergeRawItemRefreshesTheStickySlot() {
        let result = DragMergeStickiness.resolve(
            raw: .item(pageLocalSlot: 1),
            stickySlot: 2,
            point: NSPoint(x: 150, y: 50),
            cellFrames: stickinessFrames,
            itemCount: 4,
            visualCellForSlot: { $0 }
        )
        XCTAssertEqual(result.candidate, .item(pageLocalSlot: 1))
        XCTAssertEqual(result.stickySlot, 1)
    }

    func testStickyMergeDropsStaleSlots() {
        let result = DragMergeStickiness.resolve(
            raw: .insertionSlot(slotIndex: 0),
            stickySlot: 9,
            point: NSPoint(x: 50, y: 50),
            cellFrames: stickinessFrames,
            itemCount: 4,
            visualCellForSlot: { $0 }
        )
        XCTAssertEqual(result.candidate, .insertionSlot(slotIndex: 0))
        XCTAssertNil(result.stickySlot)
    }

    // MARK: Root-level planning

    private func app(_ name: String) -> AppItem {
        AppItem(
            identifier: "app.\(name.lowercased())",
            bundleIdentifier: nil,
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            creationDate: nil,
            modificationDate: nil
        )
    }

    private func folder(_ name: String, apps: [AppItem]) -> AppFolder {
        AppFolder(identifier: "folder.\(name.lowercased())", name: name, apps: apps, isSystem: false)
    }

    private func rootContext(
        items: [LunchpadItem],
        draggedIndex: Int,
        pageStart: Int = 0
    ) -> GridDragContext {
        GridDragContext(
            isRootLevel: true,
            folderIdentifier: nil,
            containerItems: items,
            rootItems: nil,
            pageStartIndex: pageStart,
            draggedContainerIndex: draggedIndex,
            newFolderName: "New Folder"
        )
    }

    func testRootReorderCommitLandsAtTheHoveredCell() {
        let items: [LunchpadItem] = [.app(app("A")), .app(app("B")), .app(app("C"))]
        let commit = DragArrangementPlanner.plan(
            context: rootContext(items: items, draggedIndex: 0),
            candidate: .insertionSlot(slotIndex: 2)
        )

        // A lands in cell 2 exactly; it never stops one cell short of the hover target.
        XCTAssertEqual(
            commit,
            .rootRearranged(slots: [
                .app(identifier: "app.b"),
                .app(identifier: "app.c"),
                .app(identifier: "app.a"),
            ])
        )
    }

    func testRootDropOnAnotherAppCreatesFolderAtTargetSlot() {
        let items: [LunchpadItem] = [.app(app("A")), .app(app("B")), .app(app("C"))]
        let commit = DragArrangementPlanner.plan(
            context: rootContext(items: items, draggedIndex: 0),
            candidate: .item(pageLocalSlot: 2)
        )

        XCTAssertEqual(
            commit,
            .folderCreated(
                name: "New Folder",
                appIdentifiers: ["app.c", "app.a"],
                insertionIndex: 1,
                remainingRootSlots: [.app(identifier: "app.b")]
            )
        )
    }

    func testRootDropBackwardOntoAppAdjustsInsertionIndex() {
        let items: [LunchpadItem] = [.app(app("A")), .app(app("B")), .app(app("C"))]
        let commit = DragArrangementPlanner.plan(
            context: rootContext(items: items, draggedIndex: 2),
            candidate: .item(pageLocalSlot: 0)
        )

        XCTAssertEqual(
            commit,
            .folderCreated(
                name: "New Folder",
                appIdentifiers: ["app.a", "app.c"],
                insertionIndex: 0,
                remainingRootSlots: [.app(identifier: "app.b")]
            )
        )
    }

    func testRootDropOntoFolderAppendsToIt() {
        let items: [LunchpadItem] = [
            .app(app("A")),
            .folder(folder("Games", apps: [app("Chess")])),
        ]
        let commit = DragArrangementPlanner.plan(
            context: rootContext(items: items, draggedIndex: 0),
            candidate: .item(pageLocalSlot: 1)
        )

        XCTAssertEqual(
            commit,
            .appAddedToFolder(
                appIdentifier: "app.a",
                folderIdentifier: "folder.games",
                rootSlots: [.folder(identifier: "folder.games")]
            )
        )
    }

    func testRootFolderDragOntoAppReordersInsteadOfMerging() {
        let items: [LunchpadItem] = [
            .app(app("A")),
            .folder(folder("Games", apps: [app("Chess")])),
        ]
        let commit = DragArrangementPlanner.plan(
            context: rootContext(items: items, draggedIndex: 1),
            candidate: .item(pageLocalSlot: 0)
        )

        XCTAssertEqual(
            commit,
            .rootRearranged(slots: [
                .folder(identifier: "folder.games"),
                .app(identifier: "app.a"),
            ])
        )
    }

    func testRootDropOnOwnSlotIsANoOp() {
        let items: [LunchpadItem] = [.app(app("A")), .app(app("B"))]
        XCTAssertNil(
            DragArrangementPlanner.plan(
                context: rootContext(items: items, draggedIndex: 0),
                candidate: .item(pageLocalSlot: 0)
            )
        )
        // Landing back in the origin cell is a no-op; the neighboring cell is a real move.
        XCTAssertNil(
            DragArrangementPlanner.plan(
                context: rootContext(items: items, draggedIndex: 0),
                candidate: .insertionSlot(slotIndex: 0)
            )
        )
        XCTAssertEqual(
            DragArrangementPlanner.plan(
                context: rootContext(items: items, draggedIndex: 0),
                candidate: .insertionSlot(slotIndex: 1)
            ),
            .rootRearranged(slots: [.app(identifier: "app.b"), .app(identifier: "app.a")])
        )
    }

    func testRootReorderAccountsForPageStart() {
        // Page 2 starts at container index 7 with three remaining items.
        let items = (0..<10).map { LunchpadItem.app(app("App\($0)")) }
        let commit = DragArrangementPlanner.plan(
            context: rootContext(items: items, draggedIndex: 8, pageStart: 7),
            candidate: .insertionSlot(slotIndex: 0)
        )

        guard case .rootRearranged(let slots) = commit else {
            return XCTFail("Expected a root rearrangement, got \(String(describing: commit))")
        }
        XCTAssertEqual(slots, [
            .app(identifier: "app.app0"),
            .app(identifier: "app.app1"),
            .app(identifier: "app.app2"),
            .app(identifier: "app.app3"),
            .app(identifier: "app.app4"),
            .app(identifier: "app.app5"),
            .app(identifier: "app.app6"),
            .app(identifier: "app.app8"),
            .app(identifier: "app.app7"),
            .app(identifier: "app.app9"),
        ])
    }

    // MARK: Folder-level planning

    private func folderContext(
        folder: AppFolder,
        draggedIndex: Int,
        rootItems: [LunchpadItem]
    ) -> GridDragContext {
        GridDragContext(
            isRootLevel: false,
            folderIdentifier: folder.identifier,
            containerItems: folder.apps.map(LunchpadItem.app),
            rootItems: rootItems,
            pageStartIndex: 0,
            draggedContainerIndex: draggedIndex,
            newFolderName: "New Folder"
        )
    }

    func testFolderReorderRearrangesMembersOnly() {
        let folder = folder("Games", apps: [app("Chess"), app("Go"), app("Cards")])
        let rootItems: [LunchpadItem] = [.folder(folder), .app(app("A"))]

        let commit = DragArrangementPlanner.plan(
            context: folderContext(folder: folder, draggedIndex: 2, rootItems: rootItems),
            candidate: .insertionSlot(slotIndex: 0)
        )

        XCTAssertEqual(
            commit,
            .folderRearranged(
                folderIdentifier: "folder.games",
                appIdentifiers: ["app.cards", "app.chess", "app.go"],
                rootSlots: [
                    .folder(identifier: "folder.games"),
                    .app(identifier: "app.a"),
                ]
            )
        )
    }

    func testFolderDropOnTitleRemovesAppNextToTheFolder() {
        let folder = folder("Games", apps: [app("Chess"), app("Go")])
        let rootItems: [LunchpadItem] = [.app(app("A")), .folder(folder), .app(app("B"))]

        let commit = DragArrangementPlanner.plan(
            context: folderContext(folder: folder, draggedIndex: 0, rootItems: rootItems),
            candidate: .removalTarget
        )

        XCTAssertEqual(
            commit,
            .appRemovedToRoot(
                appIdentifier: "app.chess",
                sourceFolderIdentifier: "folder.games",
                rootSlots: [
                    .app(identifier: "app.a"),
                    .folder(identifier: "folder.games"),
                    .app(identifier: "app.chess"),
                    .app(identifier: "app.b"),
                ]
            )
        )
    }

    func testFolderDropOnAnotherAppReordersInsteadOfCreatingNestedFolders() {
        let folder = folder("Games", apps: [app("Chess"), app("Go")])
        let rootItems: [LunchpadItem] = [.folder(folder)]

        let commit = DragArrangementPlanner.plan(
            context: folderContext(folder: folder, draggedIndex: 1, rootItems: rootItems),
            candidate: .item(pageLocalSlot: 0)
        )

        XCTAssertEqual(
            commit,
            .folderRearranged(
                folderIdentifier: "folder.games",
                appIdentifiers: ["app.go", "app.chess"],
                rootSlots: [.folder(identifier: "folder.games")]
            )
        )
    }
}
