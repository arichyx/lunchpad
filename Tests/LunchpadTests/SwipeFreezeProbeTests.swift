import AppKit
import XCTest
@testable import Lunchpad

/// Diagnostic probe for the empty-space drag freeze: drives a realistic high-frequency mouse
/// drag through a visible window, times every phase, and checks the pager cannot wedge the UI.
@MainActor
final class SwipeFreezeProbeTests: XCTestCase {
    private var window: NSWindow!
    private var grid: IconGridView!
    private var collectionView: LunchpadCollectionView!

    override func tearDown() {
        window?.orderOut(nil)
        window = nil
        grid = nil
        collectionView = nil
        super.tearDown()
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

    private func makeGrid(itemCount: Int, visible: Bool) {
        let items = (0..<itemCount).map { index in LunchpadItem.app(app("App\(index)")) }
        grid = IconGridView(items: items, localizer: AppLocalizer(language: .english))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1600, height: 1000),
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
        if visible {
            window.orderFrontRegardless()
        }
    }

    /// Uses the production LunchpadWindow event boundary rather than a plain NSWindow, so active
    /// swipe routing is tested before AppKit can hand drag/up to another subview.
    private func makeRoutedWindow(itemCount: Int) {
        let items = (0..<itemCount).map { index in LunchpadItem.app(app("App\(index)")) }
        let defaults = UserDefaults(suiteName: "SwipeFreezeProbeTests.\(UUID().uuidString)")!
        let routedWindow = LunchpadWindow(
            items: items,
            localizer: AppLocalizer(language: .english),
            rootPageStore: RootPageStore(defaults: defaults)
        )
        routedWindow.setFrame(
            NSRect(x: 0, y: 0, width: 1600, height: 1000),
            display: false
        )
        window = routedWindow
        grid = routedWindow.contentView?.subviews.compactMap { $0 as? IconGridView }.first
        grid.updateScreenInsets(
            NSEdgeInsets(top: 40, left: 0, bottom: 40, right: 0),
            availableHeight: 1000
        )
        routedWindow.contentView?.layoutSubtreeIfNeeded()
        grid.layoutSubtreeIfNeeded()
        collectionView = grid.subviews.compactMap { $0 as? LunchpadCollectionView }.first
        routedWindow.orderFrontRegardless()
        routedWindow.makeKey()
    }

    private func event(
        _ type: NSEvent.EventType,
        at pointInCollectionView: NSPoint,
        timestamp: TimeInterval
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: collectionView.convert(pointInCollectionView, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    private func backgroundPoint() -> NSPoint? {
        guard let first = collectionView.item(at: IndexPath(item: 0, section: 0))?.view.frame,
              let second = collectionView.item(at: IndexPath(item: 1, section: 0))?.view.frame
        else { return nil }
        return NSPoint(x: (first.maxX + second.minX) / 2, y: first.midY)
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// 120 small drag deltas at 120 Hz — the shape a real trackpad/mouse drag produces.
    private func realisticDrag(from start: NSPoint, total: CGFloat) throws -> TimeInterval {
        let steps = 120
        let dt: TimeInterval = 1.0 / 120
        let step = total / CGFloat(steps)
        let begin = Date()
        collectionView.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, at: start, timestamp: 0)))
        var worstEvent: TimeInterval = 0
        for index in 1...steps {
            let point = NSPoint(x: start.x + step * CGFloat(index), y: start.y)
            let before = Date()
            collectionView.mouseDragged(
                with: try XCTUnwrap(event(.leftMouseDragged, at: point, timestamp: dt * TimeInterval(index)))
            )
            worstEvent = max(worstEvent, -before.timeIntervalSinceNow)
        }
        let dragElapsed = -begin.timeIntervalSinceNow
        collectionView.mouseUp(
            with: try XCTUnwrap(event(
                .leftMouseUp,
                at: NSPoint(x: start.x + total, y: start.y),
                timestamp: dt * TimeInterval(steps + 1)
            ))
        )
        print("PROBE drag total=\(dragElapsed)s worstSingleEvent=\(worstEvent)s pagerActive=\(grid.isSwipePagingActive)")
        return dragElapsed
    }

    func testProbeRealisticDragVisibleWindow() throws {
        makeGrid(itemCount: 70, visible: true)
        try XCTSkipUnless(collectionView.frame.width > 100)
        let start = try XCTUnwrap(backgroundPoint())
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction

        // Warm pass first (cache cold start), then a measured second swipe.
        _ = try realisticDrag(from: start, total: -threshold - 60)
        pump(0.6)
        print("PROBE after first swipe: pagerActive=\(grid.isSwipePagingActive) page=\(grid.currentPage)")

        let elapsed = try realisticDrag(from: start, total: threshold + 60)
        pump(0.6)
        print("PROBE after second swipe: pagerActive=\(grid.isSwipePagingActive) page=\(grid.currentPage)")
        XCTAssertLessThan(elapsed, 1.0, "A 120-event drag must not take a second")
        XCTAssertFalse(grid.isSwipePagingActive, "The pager must be torn down after the settle")
    }

    private func gridEvent(
        _ type: NSEvent.EventType,
        at pointInGrid: NSPoint,
        timestamp: TimeInterval
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: grid.convert(pointInGrid, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    func testProbeOuterBackgroundRealisticDrag() throws {
        makeGrid(itemCount: 70, visible: true)
        try XCTSkipUnless(collectionView.frame.width > 100)
        // The outer margin left of the grid — the easiest "empty space" to grab.
        let start = NSPoint(x: collectionView.frame.minX - 60, y: collectionView.frame.midY)
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction
        let steps = 120
        let dt: TimeInterval = 1.0 / 120
        let total = -threshold - 60
        let step = total / CGFloat(steps)

        let begin = Date()
        grid.mouseDown(with: try XCTUnwrap(gridEvent(.leftMouseDown, at: start, timestamp: 0)))
        var worstEvent: TimeInterval = 0
        for index in 1...steps {
            let before = Date()
            grid.mouseDragged(
                with: try XCTUnwrap(gridEvent(
                    .leftMouseDragged,
                    at: NSPoint(x: start.x + step * CGFloat(index), y: start.y),
                    timestamp: dt * TimeInterval(index)
                ))
            )
            worstEvent = max(worstEvent, -before.timeIntervalSinceNow)
        }
        let dragElapsed = -begin.timeIntervalSinceNow
        grid.mouseUp(
            with: try XCTUnwrap(gridEvent(
                .leftMouseUp,
                at: NSPoint(x: start.x + total, y: start.y),
                timestamp: dt * TimeInterval(steps + 1)
            ))
        )
        pump(0.6)
        print("PROBE outer drag total=\(dragElapsed)s worstEvent=\(worstEvent)s pagerActive=\(grid.isSwipePagingActive) page=\(grid.currentPage) standby=\(collectionView.isSwipeStandby)")
        XCTAssertLessThan(dragElapsed, 1.0)
        XCTAssertEqual(grid.currentPage, 1)
        XCTAssertFalse(grid.isSwipePagingActive)
        XCTAssertFalse(collectionView.isSwipeStandby)
    }

    /// Reproduces the real event routing once a grid-gap swipe hides the tracked collection
    /// view: activation happens in the collection view, but later drag and mouse-up events are
    /// re-routed through the responder chain to the grid. The swipe must still follow, conclude,
    /// and tear down the pager — previously this wedged the whole launcher.
    func testProbeGridGapSwipeRoutedThroughResponderChain() throws {
        makeGrid(itemCount: 70, visible: false)
        try XCTSkipUnless(collectionView.frame.width > 100)
        let gap = try XCTUnwrap(backgroundPoint())
        let gapInGrid = grid.convert(gap, from: collectionView)
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction

        // Press between icons; the sub-threshold move still reaches the collection view.
        collectionView.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, at: gap, timestamp: 0)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(event(
                .leftMouseDragged,
                at: NSPoint(x: gap.x - 30, y: gap.y),
                timestamp: 0.1
            ))
        )
        XCTAssertTrue(collectionView.isSwipeTracking)
        XCTAssertTrue(grid.isSwipePagingActive, "The pager covers the grid once the swipe activates")

        // The pager's clip is hit-test transparent and the collection view is hidden, so the
        // remaining events arrive at the grid instead.
        grid.mouseDragged(
            with: try XCTUnwrap(gridEvent(
                .leftMouseDragged,
                at: NSPoint(x: gapInGrid.x - threshold - 80, y: gapInGrid.y),
                timestamp: 0.5
            ))
        )
        XCTAssertEqual(grid.swipePagerTranslation, -(threshold + 80), accuracy: 2)

        grid.mouseUp(
            with: try XCTUnwrap(gridEvent(
                .leftMouseUp,
                at: NSPoint(x: gapInGrid.x - threshold - 80, y: gapInGrid.y),
                timestamp: 0.6
            ))
        )
        pump(0.6)

        XCTAssertFalse(collectionView.isSwipeTracking, "The routed mouse-up must conclude the swipe")
        XCTAssertFalse(grid.isSwipePagingActive, "The pager must be torn down after the routed release")
        XCTAssertFalse(collectionView.isSwipeStandby)
        XCTAssertEqual(grid.currentPage, 1)
    }

    /// Full-fidelity routing probe: events go through `window.sendEvent`, so AppKit's own
    /// hit-testing and last-hit tracking decide which view receives them — exactly like a real
    /// gesture. This is the path a grid-gap swipe takes on a live machine.
    func testProbeSendEventRoutedGapSwipe() throws {
        makeGrid(itemCount: 70, visible: true)
        try XCTSkipUnless(collectionView.frame.width > 100)
        let gap = try XCTUnwrap(backgroundPoint())
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction

        func windowEvent(
            _ type: NSEvent.EventType,
            collectionViewPoint: NSPoint,
            timestamp: TimeInterval
        ) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: collectionView.convert(collectionViewPoint, to: nil),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
        }

        window.makeKey()
        // Start from a gap on the RIGHT side so even the full-threshold drag stays in-window:
        // off-window points fail hit-testing and the event is dropped, which no real in-screen
        // drag can trigger.
        let rightGap = NSPoint(x: collectionView.bounds.maxX - 130, y: gap.y)
        window.sendEvent(try windowEvent(.leftMouseDown, collectionViewPoint: rightGap, timestamp: 0))
        window.sendEvent(try windowEvent(
            .leftMouseDragged,
            collectionViewPoint: NSPoint(x: rightGap.x - 30, y: rightGap.y),
            timestamp: 0.1
        ))
        print("PROBE sendEvent after sub-threshold: cvTracking=\(collectionView.isSwipeTracking)")
        XCTAssertTrue(collectionView.isSwipeTracking, "Activation must happen while the view is visible")

        window.sendEvent(try windowEvent(
            .leftMouseDragged,
            collectionViewPoint: NSPoint(x: rightGap.x - threshold - 80, y: rightGap.y),
            timestamp: 0.5
        ))
        let midPoint = collectionView.convert(
            NSPoint(x: rightGap.x - threshold - 80, y: rightGap.y),
            to: nil
        )
        print("PROBE sendEvent mid-drag: translation=\(grid.swipePagerTranslation) pagerActive=\(grid.isSwipePagingActive) standby=\(collectionView.isSwipeStandby)")
        print("PROBE hitTest at mid point: \(String(describing: window.contentView?.hitTest(midPoint)))")
        print("PROBE grid hitTest: \(String(describing: grid.hitTest(grid.convert(midPoint, from: nil))))")

        window.sendEvent(try windowEvent(
            .leftMouseUp,
            collectionViewPoint: NSPoint(x: rightGap.x - threshold - 80, y: rightGap.y),
            timestamp: 0.6
        ))
        pump(0.6)
        print("PROBE sendEvent after up: page=\(grid.currentPage) pagerActive=\(grid.isSwipePagingActive) standby=\(collectionView.isSwipeStandby)")

        XCTAssertEqual(grid.currentPage, 1)
        XCTAssertFalse(grid.isSwipePagingActive)
        XCTAssertFalse(collectionView.isSwipeStandby)
    }

    func testProductionWindowFinishesGapSwipeReleasedOverSearchField() throws {
        makeRoutedWindow(itemCount: 70)
        try XCTSkipUnless(collectionView.frame.width > 100)
        let gap = try XCTUnwrap(backgroundPoint())
        let searchField = try XCTUnwrap(
            grid.subviews.compactMap { $0 as? LunchpadSearchField }.first
        )
        let releasePoint = NSPoint(x: searchField.frame.midX, y: searchField.frame.midY)

        window.sendEvent(try XCTUnwrap(event(.leftMouseDown, at: gap, timestamp: 0)))
        window.sendEvent(try XCTUnwrap(event(
            .leftMouseDragged,
            at: NSPoint(x: gap.x - 40, y: gap.y),
            timestamp: 0.1
        )))
        XCTAssertTrue(collectionView.isSwipeTracking)
        XCTAssertTrue(grid.isSwipePagingActive)

        // Without the window-owned route, AppKit hit-tests this mouse-up to the search field and
        // the collection tracker never ends, leaving the pager wedged indefinitely.
        window.sendEvent(try XCTUnwrap(gridEvent(
            .leftMouseDragged,
            at: releasePoint,
            timestamp: 0.2
        )))
        window.sendEvent(try XCTUnwrap(gridEvent(
            .leftMouseUp,
            at: releasePoint,
            timestamp: 0.3
        )))
        pump(0.6)

        XCTAssertFalse(collectionView.isSwipeTracking)
        XCTAssertFalse(collectionView.isSwipeStandby)
        XCTAssertFalse(grid.isSwipePagingActive)
    }

    func testProbeWedgeAfterQuickSuccessiveSwipes() throws {
        makeGrid(itemCount: 70, visible: false)
        try XCTSkipUnless(collectionView.frame.width > 100)
        let start = try XCTUnwrap(backgroundPoint())
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction

        // Release, then start a new swipe INSIDE the previous settle window.
        collectionView.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, at: start, timestamp: 0)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(event(
                .leftMouseDragged,
                at: NSPoint(x: start.x - threshold - 60, y: start.y),
                timestamp: 1.0
            ))
        )
        collectionView.mouseUp(
            with: try XCTUnwrap(event(
                .leftMouseUp,
                at: NSPoint(x: start.x - threshold - 60, y: start.y),
                timestamp: 1.1
            ))
        )
        pump(0.1) // settle still in flight
        collectionView.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, at: start, timestamp: 2.0)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(event(
                .leftMouseDragged,
                at: NSPoint(x: start.x - threshold - 60, y: start.y),
                timestamp: 3.0
            ))
        )
        collectionView.mouseUp(
            with: try XCTUnwrap(event(
                .leftMouseUp,
                at: NSPoint(x: start.x - threshold - 60, y: start.y),
                timestamp: 3.1
            ))
        )
        pump(0.8)
        print("PROBE successive: pagerActive=\(grid.isSwipePagingActive) page=\(grid.currentPage) standby=\(collectionView.isSwipeStandby)")
        XCTAssertFalse(grid.isSwipePagingActive, "A quick second swipe must not leave the pager wedged")
        XCTAssertFalse(collectionView.isSwipeStandby)
    }

    func testProbeWedgeAfterReloadDuringSettle() throws {
        makeGrid(itemCount: 70, visible: false)
        try XCTSkipUnless(collectionView.frame.width > 100)
        let start = try XCTUnwrap(backgroundPoint())
        let threshold = grid.bounds.width * GridSwipePolicy.commitFraction

        collectionView.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, at: start, timestamp: 0)))
        collectionView.mouseDragged(
            with: try XCTUnwrap(event(
                .leftMouseDragged,
                at: NSPoint(x: start.x - threshold - 60, y: start.y),
                timestamp: 1.0
            ))
        )
        collectionView.mouseUp(
            with: try XCTUnwrap(event(
                .leftMouseUp,
                at: NSPoint(x: start.x - threshold - 60, y: start.y),
                timestamp: 1.1
            ))
        )
        pump(0.05) // mid-settle
        grid.updateItems(
            (0..<70).map { LunchpadItem.app(app("App\($0)")) },
            animated: false,
            invalidatedIconPaths: []
        )
        pump(0.8)
        print("PROBE reload-during-settle: pagerActive=\(grid.isSwipePagingActive) page=\(grid.currentPage) standby=\(collectionView.isSwipeStandby)")
        XCTAssertFalse(grid.isSwipePagingActive)
        XCTAssertFalse(collectionView.isSwipeStandby)
    }
}
