import AppKit
import QuartzCore
import XCTest
@testable import Lunchpad

/// Headless end-to-end drag interaction tests: a real IconGridView in an offscreen window,
/// driven by synthetic mouse events, asserting the committed arrangement.
@MainActor
final class DragInteractionTests: XCTestCase {
    private var window: NSWindow!
    private var grid: IconGridView!
    private var collectionView: LunchpadCollectionView!
    private var commits: [LunchpadDragCommit]!

    override func setUp() {
        super.setUp()
        makeGrid(itemCount: 5)
    }

    private func makeGrid(itemCount: Int) {
        let items = (0..<itemCount).map { index in
            LunchpadItem.app(app("App\(index)"))
        }
        grid = IconGridView(items: items, localizer: AppLocalizer(language: .english))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: -5000, width: 1600, height: 1000),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = grid
        grid.updateScreenInsets(
            NSEdgeInsets(top: 40, left: 0, bottom: 40, right: 0),
            availableHeight: 1000
        )
        grid.layoutSubtreeIfNeeded()
        collectionView = grid.subviews.compactMap { $0 as? LunchpadCollectionView }.first
        commits = []
        grid.onDragCommit = { [weak self] commit in
            self?.commits.append(commit)
        }
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    override func tearDown() {
        grid = nil
        window = nil
        collectionView = nil
        commits = nil
        super.tearDown()
    }

    private func app(_ name: String) -> AppItem {
        AppItem(
            identifier: "app.\(name.lowercased())",
            bundleIdentifier: "app.\(name.lowercased())",
            name: name,
            // Reuse one real bundle icon so a page reload cannot spend longer than the
            // transition duration resolving dozens of synthetic, nonexistent paths.
            url: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
            creationDate: nil,
            modificationDate: nil
        )
    }

    /// The on-screen center of the item's icon artwork, in collection-view coordinates.
    private func artworkCenter(ofItem item: Int) -> NSPoint? {
        guard let cell = collectionView.item(at: IndexPath(item: item, section: 0)) else {
            return nil
        }
        guard let icon = cell.view.subviews.first(where: { $0 is NSImageView }) else {
            return nil
        }
        let frameInCollectionView = icon.convert(icon.bounds, to: collectionView)
        return NSPoint(x: frameInCollectionView.midX, y: frameInCollectionView.midY)
    }

    private func syntheticEvent(_ type: NSEvent.EventType, at pointInCollectionView: NSPoint) -> NSEvent? {
        let locationInWindow = collectionView.convert(pointInCollectionView, to: nil)
        return NSEvent.mouseEvent(
            with: type,
            location: locationInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    private func runUntilCommitCount(_ count: Int, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while commits.count < count, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return commits.count >= count
    }

    private func dragAcrossOnePage(direction: Int) throws {
        let start = try XCTUnwrap(artworkCenter(ofItem: 0))
        let edgeX = direction > 0
            ? collectionView.bounds.maxX + 30
            : collectionView.bounds.minX - 30
        let beyondEdge = NSPoint(x: edgeX, y: start.y)

        collectionView.mouseDown(with: try XCTUnwrap(syntheticEvent(.leftMouseDown, at: start)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x + CGFloat(direction * 20), y: start.y)
            ))
        )
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: beyondEdge))
        )
        pump(0.8)
        assertVisibleItemFramesAreDistinct()
    }

    private func dragGhost() throws -> NSView {
        let subviews = grid.subviews
        guard subviews.count >= 2 else {
            throw XCTSkip("Drag feedback views were not installed")
        }
        return subviews[subviews.count - 2]
    }

    private func assertGhostIsVisibleAndClear(_ ghost: NSView) throws {
        XCTAssertFalse(ghost.isHidden, "Cross-page insertion should show an independent ghost")
        XCTAssertGreaterThan(ghost.alphaValue, 0.1, "The insertion ghost must remain perceptible")
        XCTAssertFalse(
            ghost.subviews.contains { $0 is NSTextField },
            "The stationary ghost should not duplicate the dragged app's label"
        )
        let ghostFrameInCollectionView = grid.convert(ghost.frame, to: collectionView)
        for cell in 0..<35 {
            guard let item = collectionView.item(at: IndexPath(item: cell, section: 0)) else {
                continue
            }
            XCTAssertFalse(
                ghostFrameInCollectionView.intersects(item.view.frame.insetBy(dx: 4, dy: 4)),
                "Ghost overlaps cell (cell): ghost=\(ghostFrameInCollectionView) cell=\(item.view.frame)"
            )
        }

        let snapshot = try XCTUnwrap(grid.subviews.last)
        XCTAssertFalse(snapshot.isHidden, "The lifted icon must stay continuous while dragging")
        let snapshotLabel = try XCTUnwrap(
            snapshot.subviews.compactMap { $0 as? NSTextField }.first
        )
        let overlapsGhost = snapshot.frame.intersects(ghost.frame)
        XCTAssertEqual(
            snapshotLabel.isHidden,
            overlapsGhost,
            "Only an overlapping snapshot label should be suppressed"
        )
    }

    private enum TransferPreviewEdge {
        case previousPage
        case nextPage
    }

    private func assertTransferPreview(
        _ item: NSView,
        toward edge: TransferPreviewEdge,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let frameInGrid = collectionView.convert(item.frame, to: grid)
        switch edge {
        case .previousPage:
            XCTAssertLessThan(frameInGrid.minX, grid.bounds.minX, file: file, line: line)
            XCTAssertGreaterThan(frameInGrid.maxX, grid.bounds.minX, file: file, line: line)
        case .nextPage:
            XCTAssertLessThan(frameInGrid.minX, grid.bounds.maxX, file: file, line: line)
            XCTAssertGreaterThan(frameInGrid.maxX, grid.bounds.maxX, file: file, line: line)
        }

        let visibleWidth = frameInGrid.intersection(grid.bounds).width
        XCTAssertGreaterThan(visibleWidth, item.frame.width * 0.25, file: file, line: line)
        XCTAssertLessThan(visibleWidth, item.frame.width * 0.60, file: file, line: line)
        XCTAssertGreaterThan(item.alphaValue, 0.2, file: file, line: line)
        XCTAssertLessThan(item.alphaValue, 0.6, file: file, line: line)
        let label = try XCTUnwrap(item.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertTrue(label.isHidden, "A cross-page transfer preview should not show a label")
    }

    private func assertVisibleItemFramesAreDistinct(file: StaticString = #filePath, line: UInt = #line) {
        var frames: [(index: Int, frame: NSRect)] = []
        for index in 0..<collectionView.numberOfItems(inSection: 0) {
            guard let item = collectionView.item(at: IndexPath(item: index, section: 0)),
                  item.view.alphaValue > 0.01 else { continue }
            frames.append((index, item.view.frame))
        }

        for first in frames.indices {
            for second in frames.indices where second > first {
                XCTAssertFalse(
                    frames[first].frame.insetBy(dx: 4, dy: 4)
                        .intersects(frames[second].frame.insetBy(dx: 4, dy: 4)),
                    "Visible cells overlap after page turn: \(frames[first].index) and \(frames[second].index)",
                    file: file,
                    line: line
                )
            }
        }
    }

    func testDraggingAOnBArtworkCreatesFolder() throws {
        try XCTSkipUnless(collectionView != nil && collectionView.frame.width > 100)

        let start = try XCTUnwrap(artworkCenter(ofItem: 0))
        let target = try XCTUnwrap(artworkCenter(ofItem: 3))

        collectionView.mouseDown(with: try XCTUnwrap(syntheticEvent(.leftMouseDown, at: start)))
        // Move past the drag activation threshold first.
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x + 20, y: start.y)
            ))
        )
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: target))
        )
        collectionView.mouseUp(with: try XCTUnwrap(syntheticEvent(.leftMouseUp, at: target)))

        XCTAssertTrue(runUntilCommitCount(1), "Drag did not commit anything")
        guard let commit = commits.first else { return }

        guard case .folderCreated = commit else {
            XCTFail("Expected folderCreated, got \(commit)")
            return
        }
    }

    func testDraggingToAnEmptySlotRearranges() throws {
        try XCTSkipUnless(collectionView != nil && collectionView.frame.width > 100)

        let start = try XCTUnwrap(artworkCenter(ofItem: 0))
        // Slot 5 is empty with only five items on the page.
        let emptySlotCenter = NSPoint(x: start.x, y: start.y + 200)

        collectionView.mouseDown(with: try XCTUnwrap(syntheticEvent(.leftMouseDown, at: start)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x + 20, y: start.y)
            ))
        )
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: emptySlotCenter))
        )
        collectionView.mouseUp(with: try XCTUnwrap(syntheticEvent(.leftMouseUp, at: emptySlotCenter)))

        XCTAssertTrue(runUntilCommitCount(1), "Drag did not commit anything")
        guard case .rootRearranged(let slots) = commits.first else {
            XCTFail("Expected rootRearranged, got \(String(describing: commits.first))")
            return
        }
        // App0 lands in the hovered row; its old slot closes up behind App1.
        XCTAssertEqual(slots.first, .app(identifier: "app.app1"))
        XCTAssertTrue(slots.contains(.app(identifier: "app.app0")), "App0 vanished: \(slots)")
    }

    func testReleasingOverTheTargetsLabelStillMerges() throws {
        try XCTSkipUnless(collectionView != nil && collectionView.frame.width > 100)

        let start = try XCTUnwrap(artworkCenter(ofItem: 0))
        // The label sits in the lower part of the cell; align there like a grab by the name.
        let labelTarget = NSPoint(x: start.x + 400, y: start.y + 45)

        collectionView.mouseDown(with: try XCTUnwrap(syntheticEvent(.leftMouseDown, at: start)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x + 20, y: start.y)
            ))
        )
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: labelTarget))
        )
        collectionView.mouseUp(with: try XCTUnwrap(syntheticEvent(.leftMouseUp, at: labelTarget)))

        XCTAssertTrue(runUntilCommitCount(1), "Drag did not commit anything")
        guard case .folderCreated = commits.first else {
            XCTFail("Expected folderCreated over the label, got \(String(describing: commits.first))")
            return
        }
    }

    func testRightToLeftApproachStillMerges() throws {
        try XCTSkipUnless(collectionView != nil && collectionView.frame.width > 100)

        let start = try XCTUnwrap(artworkCenter(ofItem: 4))
        let target = try XCTUnwrap(artworkCenter(ofItem: 1))
        // Cross the open space between columns, then the target's right border area, like a
        // hand approaching from the right.
        let gap = NSPoint(x: target.x + 100, y: target.y)
        let margin = NSPoint(x: target.x + 55, y: target.y)

        collectionView.mouseDown(with: try XCTUnwrap(syntheticEvent(.leftMouseDown, at: start)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x - 20, y: start.y)
            ))
        )
        collectionView.mouseDragged(with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: gap)))
        collectionView.mouseDragged(with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: margin)))
        collectionView.mouseDragged(with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: target)))
        collectionView.mouseUp(with: try XCTUnwrap(syntheticEvent(.leftMouseUp, at: target)))

        XCTAssertTrue(runUntilCommitCount(1), "Drag did not commit anything")
        guard case .folderCreated = commits.first else {
            XCTFail("Expected folderCreated on right-to-left approach, got \(String(describing: commits.first))")
            return
        }
    }

    func testApproachThroughTheCellEdgeStillMerges() throws {
        try XCTSkipUnless(collectionView != nil && collectionView.frame.width > 100)

        let start = try XCTUnwrap(artworkCenter(ofItem: 0))
        let target = try XCTUnwrap(artworkCenter(ofItem: 3))
        // Cross the open space between columns, then the target's left margin, exactly like a
        // slow hand approaching: most of the approach happens outside any cell's frame.
        let gap = NSPoint(x: target.x - 100, y: target.y)
        let margin = NSPoint(x: target.x - 55, y: target.y)

        collectionView.mouseDown(with: try XCTUnwrap(syntheticEvent(.leftMouseDown, at: start)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x + 20, y: start.y)
            ))
        )
        collectionView.mouseDragged(with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: gap)))
        collectionView.mouseDragged(with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: margin)))
        collectionView.mouseDragged(with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: target)))
        collectionView.mouseUp(with: try XCTUnwrap(syntheticEvent(.leftMouseUp, at: target)))

        XCTAssertTrue(runUntilCommitCount(1), "Drag did not commit anything")
        guard case .folderCreated = commits.first else {
            XCTFail("Expected folderCreated after edge approach, got \(String(describing: commits.first))")
            return
        }
    }
    func testCrossPageDropOntoAnIconMerges() throws {
        makeGrid(itemCount: 40)
        try XCTSkipUnless(collectionView != nil && collectionView.frame.width > 100)

        let start = try XCTUnwrap(artworkCenter(ofItem: 0))
        // Push beyond the grid's right edge and dwell there until the page turns.
        let beyondEdge = NSPoint(x: collectionView.bounds.maxX + 30, y: start.y)

        collectionView.mouseDown(with: try XCTUnwrap(syntheticEvent(.leftMouseDown, at: start)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x + 20, y: start.y)
            ))
        )
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: beyondEdge))
        )
        pump(0.8)

        // Page 2 is now visible; move straight onto its first icon and release.
        let target = try XCTUnwrap(artworkCenter(ofItem: 0))
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: target))
        )
        collectionView.mouseUp(with: try XCTUnwrap(syntheticEvent(.leftMouseUp, at: target)))

        XCTAssertTrue(runUntilCommitCount(1), "Drag did not commit anything")
        guard case .folderCreated = commits.first else {
            XCTFail("Expected folderCreated across pages, got \(String(describing: commits.first))")
            return
        }
    }

    func testPageTurnDuringDragKeepsPushAnimation() throws {
        makeGrid(itemCount: 70)
        try XCTSkipUnless(collectionView != nil && collectionView.frame.width > 100)

        let start = try XCTUnwrap(artworkCenter(ofItem: 0))
        collectionView.mouseDown(with: try XCTUnwrap(syntheticEvent(.leftMouseDown, at: start)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x + 20, y: start.y)
            ))
        )

        grid.showNextPage()

        let transition = try XCTUnwrap(grid.lastPageTransition)
        XCTAssertEqual(transition.type, .push)
        XCTAssertEqual(transition.subtype, .fromRight)
        let snapshot = try XCTUnwrap(grid.subviews.last)
        XCTAssertFalse(snapshot.isHidden, "The lifted icon must remain above the page transition")
        grid.cancelActiveDrag()
    }

    func testCatalogReloadCancelsPendingDragCommit() throws {
        try XCTSkipUnless(collectionView != nil && collectionView.frame.width > 100)

        let start = try XCTUnwrap(artworkCenter(ofItem: 0))
        let target = try XCTUnwrap(artworkCenter(ofItem: 3))
        collectionView.mouseDown(with: try XCTUnwrap(syntheticEvent(.leftMouseDown, at: start)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x + 20, y: start.y)
            ))
        )
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: target))
        )
        collectionView.mouseUp(with: try XCTUnwrap(syntheticEvent(.leftMouseUp, at: target)))

        let reloadedItems = (0..<5).map { index in
            LunchpadItem.app(app("App\(index)"))
        }
        grid.updateItems(reloadedItems, animated: false, invalidatedIconPaths: [])
        pump(0.35)

        XCTAssertTrue(
            commits.isEmpty,
            "A delayed commit from a drag cancelled by catalog reload must be ignored"
        )
    }

    func testCrossPageForwardInsertionShowsIndependentGhost() throws {
        makeGrid(itemCount: 70) // two full pages
        try XCTSkipUnless(collectionView != nil && collectionView.frame.width > 100)

        try dragAcrossOnePage(direction: 1)

        let leadingItem = try XCTUnwrap(
            collectionView.item(at: IndexPath(item: 0, section: 0))
        ).view
        let firstCell = leadingItem.frame
        // Stay outside the artwork, so this is an insertion rather than a merge.
        let insertionPoint = NSPoint(x: firstCell.minX + 4, y: firstCell.midY)
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: insertionPoint))
        )
        pump(0.25)

        assertVisibleItemFramesAreDistinct()
        try assertTransferPreview(leadingItem, toward: .previousPage)
        try assertGhostIsVisibleAndClear(dragGhost())

        collectionView.mouseUp(
            with: try XCTUnwrap(syntheticEvent(.leftMouseUp, at: insertionPoint))
        )
        XCTAssertTrue(runUntilCommitCount(1), "Cross-page insertion did not commit")
        guard case .rootRearranged = commits.first else {
            return XCTFail("Expected rootRearranged, got \(String(describing: commits.first))")
        }
    }

    func testCrossPageForwardInsertionAtLastCellKeepsGhostAndSnapshotReadable() throws {
        makeGrid(itemCount: 70)
        try XCTSkipUnless(collectionView != nil && collectionView.frame.width > 100)

        try dragAcrossOnePage(direction: 1)

        let lastCell = try XCTUnwrap(
            collectionView.item(at: IndexPath(item: 34, section: 0))
        ).view.frame
        // Stay on the occupied cell's outer edge, which resolves to insertion at the last cell
        // instead of merging with the icon artwork.
        let insertionPoint = NSPoint(x: lastCell.maxX - 4, y: lastCell.midY)
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: insertionPoint))
        )
        pump(0.25)

        assertVisibleItemFramesAreDistinct()
        try assertGhostIsVisibleAndClear(dragGhost())

        collectionView.mouseUp(
            with: try XCTUnwrap(syntheticEvent(.leftMouseUp, at: insertionPoint))
        )
        XCTAssertTrue(runUntilCommitCount(1), "Cross-page insertion did not commit")
    }

    func testCrossPageBackwardInsertionPushesOverflowToNextPageAndShowsGhost() throws {
        makeGrid(itemCount: 70) // two full pages
        try XCTSkipUnless(collectionView != nil && collectionView.frame.width > 100)

        grid.showNextPage()
        pump(0.35)
        try dragAcrossOnePage(direction: -1)

        let firstCell = try XCTUnwrap(
            collectionView.item(at: IndexPath(item: 0, section: 0))
        ).view.frame
        let trailingItem = try XCTUnwrap(
            collectionView.item(at: IndexPath(item: 34, section: 0))
        ).view
        let insertionPoint = NSPoint(x: firstCell.minX + 4, y: firstCell.midY)
        collectionView.mouseDragged(
            with: try XCTUnwrap(syntheticEvent(.leftMouseDragged, at: insertionPoint))
        )
        pump(0.25)

        assertVisibleItemFramesAreDistinct()
        try assertTransferPreview(trailingItem, toward: .nextPage)
        try assertGhostIsVisibleAndClear(dragGhost())

        collectionView.mouseUp(
            with: try XCTUnwrap(syntheticEvent(.leftMouseUp, at: insertionPoint))
        )
        XCTAssertTrue(runUntilCommitCount(1), "Cross-page insertion did not commit")
        guard case .rootRearranged = commits.first else {
            return XCTFail("Expected rootRearranged, got \(String(describing: commits.first))")
        }
    }
}
