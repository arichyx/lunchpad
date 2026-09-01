import AppKit
import XCTest
@testable import Lunchpad

/// Decision-rule tests for swipe paging: activation, rubber banding, and release commit.
final class GridSwipePolicyTests: XCTestCase {
    func testActivationRequiresHorizontalTravel() {
        XCTAssertFalse(GridSwipePolicy.shouldActivate(dx: 5, dy: 0), "Too short to leave click territory")
        XCTAssertTrue(GridSwipePolicy.shouldActivate(dx: 12, dy: 0))
        // A predominantly vertical movement must not become a swipe.
        XCTAssertFalse(GridSwipePolicy.shouldActivate(dx: 30, dy: 40))
        XCTAssertTrue(GridSwipePolicy.shouldActivate(dx: 40, dy: 30))
    }

    func testTranslationPassesThroughWithANeighbor() {
        XCTAssertEqual(GridSwipePolicy.displayTranslation(raw: -300, hasNeighbor: true), -300)
        XCTAssertEqual(GridSwipePolicy.displayTranslation(raw: 220, hasNeighbor: true), 220)
    }

    func testTranslationRubberBandsWithoutANeighbor() {
        XCTAssertEqual(
            GridSwipePolicy.displayTranslation(raw: 200, hasNeighbor: false),
            200 * GridSwipePolicy.rubberBandDamping,
            accuracy: 0.001
        )
        XCTAssertEqual(
            GridSwipePolicy.displayTranslation(raw: -300, hasNeighbor: false),
            -300 * GridSwipePolicy.rubberBandDamping,
            accuracy: 0.001
        )
    }

    func testCommitByDistance() {
        let width: CGFloat = 1344
        let threshold = width * GridSwipePolicy.commitFraction
        XCTAssertEqual(
            GridSwipePolicy.commitDirection(translation: -threshold, velocity: 0, pagerWidth: width),
            1,
            "Dragging left past the threshold commits the next page"
        )
        XCTAssertEqual(
            GridSwipePolicy.commitDirection(translation: threshold, velocity: 0, pagerWidth: width),
            -1,
            "Dragging right past the threshold commits the previous page"
        )
        XCTAssertEqual(
            GridSwipePolicy.commitDirection(translation: -threshold + 1, velocity: 0, pagerWidth: width),
            0,
            "Just under the threshold snaps back"
        )
    }

    func testCommitByFlingVelocity() {
        let width: CGFloat = 1344
        XCTAssertEqual(
            GridSwipePolicy.commitDirection(translation: -30, velocity: -600, pagerWidth: width),
            1,
            "A fast leftward fling commits even with little travel"
        )
        XCTAssertEqual(
            GridSwipePolicy.commitDirection(translation: -200, velocity: 800, pagerWidth: width),
            -1,
            "A rightward fling dominates a leftward position"
        )
        XCTAssertEqual(
            GridSwipePolicy.commitDirection(translation: 30, velocity: 400, pagerWidth: width),
            0,
            "Neither distance nor velocity crosses a threshold"
        )
    }
}

/// State-machine tests for the shared swipe gesture tracker.
final class GridSwipeTrackerTests: XCTestCase {
    func testActivationIsGatedByTheCandidate() {
        let tracker = GridSwipeTracker()
        tracker.begin(at: NSPoint(x: 100, y: 100))
        XCTAssertFalse(
            tracker.drag(to: NSPoint(x: 200, y: 100), timestamp: 1) { false },
            "Paging must not start when the candidate denies it"
        )
        XCTAssertFalse(tracker.isActive)
        XCTAssertTrue(
            tracker.drag(to: NSPoint(x: 200, y: 100), timestamp: 2) { true }
        )
        XCTAssertTrue(tracker.isActive)
    }

    func testMovedReportsTotalTranslation() {
        let tracker = GridSwipeTracker()
        var reported: [CGFloat] = []
        tracker.onMoved = { reported.append($0) }
        tracker.begin(at: NSPoint(x: 500, y: 100))
        _ = tracker.drag(to: NSPoint(x: 460, y: 100), timestamp: 1) { true }
        _ = tracker.drag(to: NSPoint(x: 300, y: 100), timestamp: 2) { true }
        XCTAssertEqual(reported, [-40, -200])
    }

    func testEndReportsTranslationAndVelocity() {
        let tracker = GridSwipeTracker()
        tracker.begin(at: NSPoint(x: 500, y: 100))
        _ = tracker.drag(to: NSPoint(x: 450, y: 100), timestamp: 1.0) { true }
        _ = tracker.drag(to: NSPoint(x: 350, y: 100), timestamp: 1.25) { true }
        let release = tracker.end()
        XCTAssertEqual(release?.translation ?? 0, -150, accuracy: 0.001)
        // The final 100 points covered in 0.25 s read as -400 points per second; a single
        // velocity sample enters the smoothing as 40% of that.
        XCTAssertEqual(release?.velocity ?? 0, -160, accuracy: 1)
    }

    func testEndWithoutActivationReturnsNothing() {
        let tracker = GridSwipeTracker()
        tracker.begin(at: NSPoint(x: 100, y: 100))
        _ = tracker.drag(to: NSPoint(x: 105, y: 100), timestamp: 1) { true }
        XCTAssertNil(tracker.end())
        XCTAssertFalse(tracker.isActive)
    }

    func testCancelIsSilent() {
        let tracker = GridSwipeTracker()
        var ended = 0
        tracker.onEnded = { _, _ in ended += 1 }
        tracker.begin(at: NSPoint(x: 500, y: 100))
        _ = tracker.drag(to: NSPoint(x: 200, y: 100), timestamp: 1) { true }
        tracker.cancel()
        XCTAssertFalse(tracker.isActive)
        XCTAssertEqual(ended, 0, "A cancelled swipe must not report a release")
    }

    func testCancelRejectsTrailingDragUntilAnotherBegin() {
        let tracker = GridSwipeTracker()
        tracker.begin(at: NSPoint(x: 500, y: 100))
        tracker.cancel()

        XCTAssertFalse(
            tracker.drag(to: NSPoint(x: 100, y: 100), timestamp: 1) { true },
            "A drag event queued before cancellation must not reactivate the old press"
        )
        tracker.begin(at: NSPoint(x: 500, y: 100))
        XCTAssertTrue(tracker.drag(to: NSPoint(x: 100, y: 100), timestamp: 2) { true })
    }
}

/// State-machine tests for the trackpad wheel swipe accumulator.
final class GridSwipeWheelTrackerTests: XCTestCase {
    func testActivationRequiresTravelAndHorizontalDominance() {
        var tracker = GridSwipeWheelTracker()
        XCTAssertNil(tracker.advance(deltaX: -5, deltaY: 0, timestamp: 1) { true })
        XCTAssertFalse(tracker.isActive)
        XCTAssertNil(
            tracker.advance(deltaX: -30, deltaY: 40, timestamp: 2) { true },
            "A vertically dominant sample must not activate"
        )
        XCTAssertEqual(tracker.advance(deltaX: -40, deltaY: 0, timestamp: 3) { true }, -75)
        XCTAssertTrue(tracker.isActive)
    }

    func testActivationIsGatedByTheCandidate() {
        var tracker = GridSwipeWheelTracker()
        XCTAssertNil(tracker.advance(deltaX: -100, deltaY: 0, timestamp: 1) { false })
        XCTAssertFalse(tracker.isActive)
        XCTAssertEqual(tracker.advance(deltaX: -100, deltaY: 0, timestamp: 2) { true }, -200)
    }

    func testRestartResetsAccumulation() {
        var tracker = GridSwipeWheelTracker()
        _ = tracker.advance(deltaX: -200, deltaY: 0, timestamp: 1) { true }
        tracker.restart()
        XCTAssertFalse(tracker.isActive)
        XCTAssertNil(tracker.advance(deltaX: -5, deltaY: 0, timestamp: 2) { true })
    }

    func testFinishReportsReleaseAndResets() {
        var tracker = GridSwipeWheelTracker()
        _ = tracker.advance(deltaX: -100, deltaY: 0, timestamp: 1) { true }
        _ = tracker.advance(deltaX: -50, deltaY: 0, timestamp: 1.1) { true }
        let release = tracker.finish(deltaX: -10, timestamp: 1.2)
        XCTAssertEqual(release?.translation ?? 0, -160, accuracy: 0.001)
        XCTAssertFalse(tracker.isActive, "Finish must reset for the next gesture")
    }

    func testFinishWithoutActivationReturnsNothing() {
        var tracker = GridSwipeWheelTracker()
        _ = tracker.advance(deltaX: -8, deltaY: 0, timestamp: 1) { true }
        XCTAssertNil(tracker.finish(deltaX: -8, timestamp: 2), "A short gesture must not activate by ending")
    }
}

/// Headless end-to-end swipe paging tests: a real IconGridView in an offscreen window, driven by
/// synthetic mouse events with controlled timestamps so release velocity is deterministic.
@MainActor
final class GridSwipeInteractionTests: XCTestCase {
    private var window: NSWindow!
    private var grid: IconGridView!
    private var collectionView: LunchpadCollectionView!
    private var backgroundClicks = 0

    override func setUp() {
        super.setUp()
        makeGrid(itemCount: 70)
    }

    override func tearDown() {
        grid = nil
        window = nil
        collectionView = nil
        super.tearDown()
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
        backgroundClicks = 0
        grid.onBackgroundClick = { [weak self] in
            self?.backgroundClicks += 1
        }
    }

    private func app(_ name: String) -> AppItem {
        AppItem(
            identifier: "app.\(name.lowercased())",
            bundleIdentifier: "app.\(name.lowercased())",
            name: name,
            url: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
            creationDate: nil,
            modificationDate: nil
        )
    }

    /// A point between the first two columns: collection-view background, not an item.
    private func backgroundPoint() -> NSPoint? {
        guard let first = collectionView.item(at: IndexPath(item: 0, section: 0))?.view.frame,
              let second = collectionView.item(at: IndexPath(item: 1, section: 0))?.view.frame
        else { return nil }
        return NSPoint(x: (first.maxX + second.minX) / 2, y: first.midY)
    }

    /// Synthetic event with an explicit timestamp offset (seconds) so velocity is deterministic.
    private func collectionEvent(
        _ type: NSEvent.EventType,
        at point: NSPoint,
        timestamp: TimeInterval
    ) -> NSEvent? {
        let locationInWindow = collectionView.convert(point, to: nil)
        return NSEvent.mouseEvent(
            with: type,
            location: locationInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Swipes the collection-view background from `start` by `dx` over one second, so velocity
    /// stays far below the fling threshold and only distance can commit.
    private func swipeBackground(from start: NSPoint, dx: CGFloat) throws {
        collectionView.mouseDown(with: try XCTUnwrap(collectionEvent(.leftMouseDown, at: start, timestamp: 0)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x + dx, y: start.y),
                timestamp: 1.0
            ))
        )
    }

    func testSwipeFollowsTheFingerAndCommitsTheNextPage() throws {
        try XCTSkipUnless(collectionView.frame.width > 100)
        let start = try XCTUnwrap(backgroundPoint())
        // Pages travel the full view width, so the commit threshold is a fraction of that.
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction

        try swipeBackground(from: start, dx: -threshold - 40)
        XCTAssertTrue(grid.isSwipePagingActive, "The finger-following pager should be on screen")
        XCTAssertTrue(collectionView.isSwipeStandby, "The real collection view goes on standby behind the pager")
        XCTAssertEqual(
            grid.swipePagerTranslation,
            -threshold - 40,
            accuracy: 2,
            "The pager must track the raw drag 1:1 toward a neighbor page"
        )
        XCTAssertEqual(grid.currentPage, 0)

        collectionView.mouseUp(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseUp,
                at: NSPoint(x: start.x - threshold - 40, y: start.y),
                timestamp: 1.1
            ))
        )
        pump(0.6)

        XCTAssertFalse(grid.isSwipePagingActive)
        XCTAssertFalse(collectionView.isSwipeStandby)
        XCTAssertEqual(grid.currentPage, 1, "Releasing past the threshold must commit the page turn")
        XCTAssertEqual(backgroundClicks, 0, "A swipe release must not close Lunchpad")
    }

    func testShortSwipeSnapsBackWithoutTurning() throws {
        try XCTSkipUnless(collectionView.frame.width > 100)
        let start = try XCTUnwrap(backgroundPoint())
        let belowThreshold = grid.bounds.width * GridSwipePolicy.commitFraction - 40

        try swipeBackground(from: start, dx: -belowThreshold)
        XCTAssertEqual(grid.swipePagerTranslation, -belowThreshold, accuracy: 2)
        XCTAssertEqual(grid.currentPage, 0)

        collectionView.mouseUp(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseUp,
                at: NSPoint(x: start.x - belowThreshold, y: start.y),
                timestamp: 1.1
            ))
        )
        pump(0.6)

        XCTAssertFalse(grid.isSwipePagingActive)
        XCTAssertEqual(grid.currentPage, 0, "An under-threshold release must snap back in place")
        XCTAssertEqual(backgroundClicks, 0)
    }

    func testSwipeTowardAMissingPageRubberBandsAndSnapsBack() throws {
        try XCTSkipUnless(collectionView.frame.width > 100)
        XCTAssertEqual(grid.currentPage, 0)
        let start = try XCTUnwrap(backgroundPoint())

        // Dragging right on the first page: no previous page exists, so the drag damps.
        try swipeBackground(from: start, dx: 200)
        XCTAssertTrue(grid.isSwipePagingActive)
        XCTAssertEqual(
            grid.swipePagerTranslation,
            200 * GridSwipePolicy.rubberBandDamping,
            accuracy: 2,
            "The first page must rubber-band instead of following the finger 1:1"
        )

        collectionView.mouseUp(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseUp,
                at: NSPoint(x: start.x + 200, y: start.y),
                timestamp: 1.1
            ))
        )
        pump(0.6)

        XCTAssertFalse(grid.isSwipePagingActive)
        XCTAssertEqual(grid.currentPage, 0)
    }

    func testSwipeSwipesThePreviousPageIntoView() throws {
        try XCTSkipUnless(collectionView.frame.width > 100)
        grid.showNextPage()
        XCTAssertEqual(grid.currentPage, 1)
        let start = try XCTUnwrap(backgroundPoint())
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction

        try swipeBackground(from: start, dx: threshold + 40)
        XCTAssertEqual(grid.swipePagerTranslation, threshold + 40, accuracy: 2)

        collectionView.mouseUp(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseUp,
                at: NSPoint(x: start.x + threshold + 40, y: start.y),
                timestamp: 1.1
            ))
        )
        pump(0.6)

        XCTAssertEqual(grid.currentPage, 0, "A rightward swipe must return to the previous page")
    }

    func testQuickSuccessiveSwipesCommitBothPageTurns() throws {
        makeGrid(itemCount: 105)
        try XCTSkipUnless(collectionView.frame.width > 100)
        let start = try XCTUnwrap(backgroundPoint())
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction

        try swipeBackground(from: start, dx: -threshold - 40)
        collectionView.mouseUp(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseUp,
                at: NSPoint(x: start.x - threshold - 40, y: start.y),
                timestamp: 1.1
            ))
        )
        pump(0.05)
        XCTAssertTrue(grid.isSwipeSettling)
        XCTAssertEqual(grid.currentPage, 0, "The first visual settle has not reached its timer yet")

        // The next press must synchronously commit the page already settling into view before it
        // resolves the new gesture's start point and neighboring pages.
        collectionView.mouseDown(
            with: try XCTUnwrap(collectionEvent(.leftMouseDown, at: start, timestamp: 2.0))
        )
        XCTAssertEqual(grid.currentPage, 1)
        XCTAssertFalse(grid.isSwipeSettling)
        collectionView.mouseDragged(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x - threshold - 40, y: start.y),
                timestamp: 3.0
            ))
        )
        collectionView.mouseUp(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseUp,
                at: NSPoint(x: start.x - threshold - 40, y: start.y),
                timestamp: 3.1
            ))
        )
        pump(0.6)

        XCTAssertEqual(grid.currentPage, 2, "Two quick forward swipes must advance two pages")
        XCTAssertFalse(grid.isSwipePagingActive)
        XCTAssertFalse(collectionView.isSwipeStandby)
    }

    func testClickDuringSettleTargetsIncomingPageInsteadOfBackground() throws {
        var items = (0..<70).map { index in LunchpadItem.app(app("App\(index)")) }
        let member = app("FolderMember")
        items[35] = .folder(AppFolder(
            identifier: "folder.incoming",
            name: "Incoming Folder",
            apps: [member],
            isSystem: false
        ))
        grid.updateItems(items, animated: false, invalidatedIconPaths: [])
        try XCTSkipUnless(collectionView.frame.width > 100)
        let gap = try XCTUnwrap(backgroundPoint())
        let firstCellFrame = try XCTUnwrap(
            collectionView.item(at: IndexPath(item: 0, section: 0))?.view.frame
        )
        let firstCellCenter = NSPoint(x: firstCellFrame.midX, y: firstCellFrame.midY)
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction

        try swipeBackground(from: gap, dx: -threshold - 40)
        collectionView.mouseUp(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseUp,
                at: NSPoint(x: gap.x - threshold - 40, y: gap.y),
                timestamp: 1.1
            ))
        )
        pump(0.05)
        XCTAssertTrue(grid.isSwipeSettling)

        // This click occurs before the settle timer. The press hook must first commit page 1,
        // then resolve the same coordinate against its real first item (the folder).
        collectionView.mouseDown(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseDown,
                at: firstCellCenter,
                timestamp: 2.0
            ))
        )
        collectionView.mouseUp(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseUp,
                at: firstCellCenter,
                timestamp: 2.1
            ))
        )

        let searchField = try XCTUnwrap(
            grid.subviews.compactMap { $0 as? LunchpadSearchField }.first
        )
        XCTAssertTrue(searchField.isHidden, "The incoming folder should open instead of closing Lunchpad")
        XCTAssertEqual(backgroundClicks, 0)
        XCTAssertFalse(grid.isSwipePagingActive)
        XCTAssertFalse(collectionView.isSwipeStandby)
    }

    func testSinglePageGridNeverStartsASwipe() throws {
        makeGrid(itemCount: 5)
        try XCTSkipUnless(collectionView.frame.width > 100)
        let start = try XCTUnwrap(backgroundPoint())

        collectionView.mouseDown(with: try XCTUnwrap(collectionEvent(.leftMouseDown, at: start, timestamp: 0)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x - 300, y: start.y),
                timestamp: 1.0
            ))
        )
        XCTAssertFalse(grid.isSwipePagingActive, "A single-page grid has nothing to swipe to")
        collectionView.mouseUp(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseUp,
                at: NSPoint(x: start.x - 300, y: start.y),
                timestamp: 1.1
            ))
        )
        pump(0.4)

        XCTAssertEqual(grid.currentPage, 0)
        XCTAssertEqual(backgroundClicks, 1, "Without pages, a background release keeps closing Lunchpad")
    }

    func testOuterBackgroundSwipeAlsoPages() throws {
        try XCTSkipUnless(collectionView.frame.width > 100)
        // A point in the outer padding, left of the collection view; events target the grid.
        let start = NSPoint(
            x: collectionView.frame.minX - 60,
            y: collectionView.frame.midY
        )
        XCTAssertFalse(collectionView.frame.contains(start))
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction

        grid.mouseDown(with: try XCTUnwrap(windowEvent(.leftMouseDown, at: start, timestamp: 0)))
        grid.mouseDragged(
            with: try XCTUnwrap(windowEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x - threshold - 40, y: start.y),
                timestamp: 1.0
            ))
        )
        XCTAssertTrue(grid.isSwipePagingActive, "The outer background must drive the same pager")
        grid.mouseUp(
            with: try XCTUnwrap(windowEvent(
                .leftMouseUp,
                at: NSPoint(x: start.x - threshold - 40, y: start.y),
                timestamp: 1.1
            ))
        )
        pump(0.6)

        XCTAssertEqual(grid.currentPage, 1)
        XCTAssertEqual(backgroundClicks, 0)
    }

    func testCatalogReloadCancelsAnInFlightSwipe() throws {
        try XCTSkipUnless(collectionView.frame.width > 100)
        let start = try XCTUnwrap(backgroundPoint())
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction

        try swipeBackground(from: start, dx: -threshold - 40)
        XCTAssertTrue(grid.isSwipePagingActive)

        let reloadedItems = (0..<70).map { index in
            LunchpadItem.app(app("App\(index)"))
        }
        grid.updateItems(reloadedItems, animated: false, invalidatedIconPaths: [])
        XCTAssertFalse(collectionView.isSwipeTracking)

        // AppKit may still deliver the tail of the physical drag after the catalog changed. It
        // must not resurrect the pager without a fresh mouse-down on the replacement content.
        collectionView.mouseDragged(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseDragged,
                at: NSPoint(x: start.x - threshold - 120, y: start.y),
                timestamp: 1.2
            ))
        )
        collectionView.mouseUp(
            with: try XCTUnwrap(collectionEvent(
                .leftMouseUp,
                at: NSPoint(x: start.x - threshold - 120, y: start.y),
                timestamp: 1.3
            ))
        )
        pump(0.4)

        XCTAssertFalse(grid.isSwipePagingActive)
        XCTAssertFalse(collectionView.isSwipeStandby)
        XCTAssertEqual(
            grid.currentPage,
            0,
            "A reload that cancels the swipe must not later commit its page turn"
        )
    }

    func testCatalogReloadIgnoresTailOfCancelledTrackpadSwipe() throws {
        try XCTSkipUnless(collectionView.frame.width > 100)

        wheel(-3, [.began], dt: 0.016)
        wheel(-100, [.changed], dt: 0.016)
        XCTAssertTrue(grid.isSwipePagingActive)

        let reloadedItems = (0..<70).map { index in
            LunchpadItem.app(app("Reloaded\(index)"))
        }
        grid.updateItems(reloadedItems, animated: false, invalidatedIconPaths: [])
        XCTAssertFalse(grid.isSwipePagingActive)

        wheel(-200, [.changed], dt: 0.016)
        wheel(0, [.ended], dt: 0.016)
        pump(0.4)
        XCTAssertFalse(grid.isSwipePagingActive, "The cancelled gesture tail must stay ignored")
        XCTAssertEqual(grid.currentPage, 0)

        // A genuinely new phase-bearing gesture remains usable.
        wheel(-3, [.began], dt: 0.016)
        wheel(-100, [.changed], dt: 0.016)
        XCTAssertTrue(grid.isSwipePagingActive)
        wheel(0, [.cancelled], dt: 0.016)
        pump(0.4)
        XCTAssertFalse(grid.isSwipePagingActive)
    }

    // MARK: Trackpad two-finger swipes

    /// Drives the collection view's internal trackpad handler; phase-bearing scroll events
    /// cannot be synthesized through public NSEvent initializers.
    private var wheelClock: TimeInterval = 0

    private func wheel(_ deltaX: CGFloat, _ phase: NSEvent.Phase, dt: TimeInterval) {
        wheelClock += dt
        collectionView.handleTrackpadWheel(
            deltaX: deltaX,
            deltaY: 0,
            phase: phase,
            timestamp: wheelClock
        )
    }

    /// The snapshot pages must mirror the real grid exactly: pages travel the full view width
    /// like the real Launchpad (icons slide across the outer margins, never cut at the grid
    /// edge), the first row sits at the visual top, the icon sits above its label, neighbors
    /// live on their correct sides, and the page indicator stays above the sliding pages.
    func testSwipePagerMatchesGridGeometry() throws {
        try XCTSkipUnless(collectionView.frame.width > 100)
        let start = try XCTUnwrap(backgroundPoint())

        try swipeBackground(from: start, dx: -60)
        XCTAssertTrue(grid.isSwipePagingActive)
        let clipView = try XCTUnwrap(
            grid.subviews.compactMap { $0 as? IconGridView.SwipePagerView }.first,
            "The pager's clip view is a direct grid subview"
        )
        XCTAssertEqual(
            clipView.frame,
            grid.bounds,
            "The clip spans the whole view so pages travel the full screen width"
        )
        XCTAssertEqual(clipView.layer?.masksToBounds ?? false, true, "Nothing may render past the screen edge")
        let pageIndicator = try XCTUnwrap(
            grid.subviews.first { $0 is PageIndicatorView }
        )
        let zOrder = try XCTUnwrap(
            [collectionView, clipView, pageIndicator].map { view in
                grid.subviews.firstIndex(where: { $0 === view })
            },
            "One of the pager z-order anchors is missing from the grid"
        )
        let (collectionZ, clipZ, indicatorZ) = (zOrder[0]!, zOrder[1]!, zOrder[2]!)
        XCTAssertLessThan(collectionZ, clipZ, "The clip replaces the collection view's z-position")
        XCTAssertLessThan(clipZ, indicatorZ, "The page indicator stays above the sliding pages")

        let contentView = try XCTUnwrap(clipView.subviews.first)
        XCTAssertTrue(contentView.isFlipped, "Slot frames come from the flipped collection view")
        XCTAssertEqual(
            contentView.frame.minX,
            -60,
            accuracy: 1,
            "The translating content view carries the drag"
        )

        let pages = contentView.subviews
        XCTAssertEqual(pages.count, 2, "A swipe with a next page shows both pages")
        let currentPageSnapshot = try XCTUnwrap(pages.first)
        let nextPageSnapshot = try XCTUnwrap(pages.last)
        let flippedPageFrame = CGRect(
            x: collectionView.frame.minX,
            y: grid.bounds.height - collectionView.frame.maxY,
            width: collectionView.frame.width,
            height: collectionView.frame.height
        )
        XCTAssertEqual(
            currentPageSnapshot.frame,
            flippedPageFrame,
            "The current page keeps the grid inset, flipped into the pager's top-based coords"
        )
        let pageUnit = grid.bounds.width
        XCTAssertEqual(
            nextPageSnapshot.frame,
            flippedPageFrame.offsetBy(dx: pageUnit, dy: 0),
            "The next page shares the current page's flipped frame, one page unit right"
        )
        XCTAssertGreaterThan(
            nextPageSnapshot.frame.maxX,
            clipView.bounds.width,
            "The untouched neighbor lies beyond the clip and stays hidden"
        )

        // The decisive check: each snapshot item must cover the exact screen region of the real
        // cell it stands in for, through every flipped and non-flipped container in between —
        // offset by however far the ongoing swipe has slid the pager.
        let items = currentPageSnapshot.subviews
        XCTAssertEqual(items.count, 35, "A full page snapshot holds every visible item")
        let firstItem = try XCTUnwrap(items.first)
        let snapshotItemFrame = grid.convert(firstItem.bounds, from: firstItem)
        let realCell = try XCTUnwrap(collectionView.item(at: IndexPath(item: 0, section: 0)))
        let realCellFrame = grid.convert(realCell.view.frame, from: collectionView)
        XCTAssertEqual(
            snapshotItemFrame.minX,
            realCellFrame.minX + grid.swipePagerTranslation,
            accuracy: 0.5,
            "Horizontal alignment, including the live swipe translation"
        )
        XCTAssertEqual(snapshotItemFrame.minY, realCellFrame.minY, accuracy: 0.5, "Vertical alignment")
        XCTAssertEqual(snapshotItemFrame.width, realCellFrame.width, accuracy: 0.5)
        XCTAssertEqual(snapshotItemFrame.height, realCellFrame.height, accuracy: 0.5)

        // The neighbor's first item must align with the real first cell plus one page unit and
        // the live translation, through the same flipped-container chain.
        let neighborFirstItem = try XCTUnwrap(nextPageSnapshot.subviews.first)
        let neighborItemFrame = grid.convert(neighborFirstItem.bounds, from: neighborFirstItem)
        XCTAssertEqual(
            neighborItemFrame.minX,
            realCellFrame.minX + pageUnit + grid.swipePagerTranslation,
            accuracy: 0.5,
            "Neighbor horizontal alignment"
        )
        XCTAssertEqual(
            neighborItemFrame.minY,
            realCellFrame.minY,
            accuracy: 0.5,
            "Neighbor vertical alignment — the incoming page must not drift from the rows"
        )

        let icon = try XCTUnwrap(firstItem.subviews.first { $0 is NSImageView })
        let label = try XCTUnwrap(firstItem.subviews.first { $0 is NSTextField })
        XCTAssertLessThan(
            icon.frame.minY,
            label.frame.minY,
            "The icon sits above its label, matching the real cells"
        )
    }

    func testTrackpadSwipeFollowsFingersAndCommits() throws {
        try XCTSkipUnless(collectionView.frame.width > 100)
        let threshold = collectionView.bounds.width * GridSwipePolicy.commitFraction

        wheel(-3, [.began], dt: 0.016)
        wheel(-100, [.changed], dt: 0.016)
        XCTAssertTrue(grid.isSwipePagingActive, "Passing the activation distance starts the pager")
        XCTAssertEqual(grid.swipePagerTranslation, -103, accuracy: 1)

        while grid.swipePagerTranslation > -(threshold + 40) {
            wheel(-30, [.changed], dt: 0.016)
        }
        XCTAssertEqual(grid.currentPage, 0, "The page must not turn while the fingers are down")
        XCTAssertTrue(collectionView.isSwipeStandby)

        wheel(0, [.ended], dt: 0.016)
        pump(0.6)

        XCTAssertFalse(grid.isSwipePagingActive)
        XCTAssertFalse(collectionView.isSwipeStandby)
        XCTAssertEqual(grid.currentPage, 1, "Releasing past the threshold must commit the turn")
    }

    func testShortTrackpadSwipeSnapsBack() throws {
        try XCTSkipUnless(collectionView.frame.width > 100)

        wheel(0, [.began], dt: 0.01)
        wheel(-100, [.changed], dt: 0.25)
        wheel(-100, [.changed], dt: 0.25)
        XCTAssertTrue(grid.isSwipePagingActive)
        XCTAssertEqual(grid.swipePagerTranslation, -200, accuracy: 1)

        wheel(0, [.ended], dt: 0.25)
        pump(0.6)

        XCTAssertEqual(grid.currentPage, 0, "A slow under-threshold swipe must snap back")
        XCTAssertFalse(collectionView.isSwipeStandby)
    }

    func testCancelledTrackpadSwipeSnapsBack() throws {
        try XCTSkipUnless(collectionView.frame.width > 100)

        wheel(0, [.began], dt: 0.01)
        wheel(-150, [.changed], dt: 0.05)
        XCTAssertTrue(grid.isSwipePagingActive)
        wheel(0, [.cancelled], dt: 0.05)
        pump(0.6)

        XCTAssertEqual(grid.currentPage, 0, "A system-cancelled gesture must not decide a turn")
        XCTAssertFalse(grid.isSwipePagingActive)
    }

    func testSinglePageTrackpadSwipeNeverStarts() throws {
        makeGrid(itemCount: 5)
        try XCTSkipUnless(collectionView.frame.width > 100)

        wheel(0, [.began], dt: 0.01)
        wheel(-200, [.changed], dt: 0.05)
        XCTAssertFalse(grid.isSwipePagingActive)
        wheel(0, [.ended], dt: 0.05)
        pump(0.4)

        XCTAssertEqual(grid.currentPage, 0)
    }

    private func windowEvent(
        _ type: NSEvent.EventType,
        at pointInGrid: NSPoint,
        timestamp: TimeInterval
    ) -> NSEvent? {
        let locationInWindow = grid.convert(pointInGrid, to: nil)
        return NSEvent.mouseEvent(
            with: type,
            location: locationInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }
}
