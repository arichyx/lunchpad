import AppKit

/// A fixed-page collection view: click an item to activate it, empty space to close, or press
/// and move to arrange. Click semantics survive: activation requires mouse-up on the pressed
/// item without the drag threshold being reached.
final class LunchpadCollectionView: NSCollectionView {
    var onBackgroundClick: (() -> Void)?
    var onPageDelta: ((Int) -> Void)?
    var onActivateItem: ((IndexPath) -> Void)?

    /// Whether a drag may start on the pressed item. Search results, for example, are not
    /// reorderable. When nil, every item is draggable.
    var onDragCandidate: ((IndexPath) -> Bool)?
    var onDragBegan: ((IndexPath, NSPoint) -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?

    /// Whether swipe paging may begin right now (multiple pages, no icon drag in flight).
    var onSwipePaging: (() -> Bool)?
    /// Gives the grid a chance to finish an earlier settle before this view resolves the new
    /// press against real collection-view cells. This keeps quick successive swipes and clicks
    /// aligned with the page currently visible on screen.
    var onSwipeGestureWillBegin: (() -> Void)?
    var onSwipeMoved: ((CGFloat) -> Void)?
    var onSwipeEnded: ((_ translation: CGFloat, _ velocity: CGFloat) -> Void)?
    /// Supplies a context menu for a secondary click on an item, or nil for none.
    var onContextMenu: ((IndexPath) -> NSMenu?)?

    private enum DragState {
        case idle
        case possible
        case active
    }

    private static let dragActivationDistance: CGFloat = 8

    private var dragState = DragState.idle
    private var dragStartPoint = NSPoint.zero
    private var accumulatedWheelDelta: CGFloat = 0
    private var lastDiscreteWheelTurnAt = 0.0
    private var pressedIndexPath: IndexPath?
    private var pressedOnBackground = false
    private let swipeTracker = GridSwipeTracker()
    private var wheelSwipe = GridSwipeWheelTracker()
    /// A reload can cancel a phase-bearing trackpad gesture while macOS still has `.changed` and
    /// `.ended` samples queued. Ignore that tail until a genuinely new `.began` arrives.
    private var ignoresWheelSwipeUntilBegan = false

    init() {
        super.init(frame: .zero)
        // The tracker reports through this view's callbacks; IconGridView drives the pager.
        swipeTracker.onMoved = { [weak self] translation in
            self?.onSwipeMoved?(translation)
        }
        swipeTracker.onEnded = { [weak self] translation, velocity in
            self?.onSwipeEnded?(translation, velocity)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        onSwipeGestureWillBegin?()
        let point = convert(event.locationInWindow, from: nil)
        pressedIndexPath = indexPathForItem(at: point)
        pressedOnBackground = pressedIndexPath == nil
        dragState = pressedIndexPath == nil ? .idle : .possible
        dragStartPoint = point
        // Always reset: a press that never saw mouse-up must not leave a stale swipe active,
        // and a fresh press takes priority over any trackpad gesture still in flight.
        swipeTracker.begin(at: point)
        wheelSwipe.restart()
        updatePressedAppearance(isInsideOriginalItem: true)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if swipeTracker.isActive {
            _ = swipeTracker.drag(to: point, timestamp: event.timestamp) { true }
            return
        }
        if pressedIndexPath == nil,
           swipeTracker.drag(to: point, timestamp: event.timestamp, canActivate: { [weak self] in
               self?.dragState != .active && (self?.onSwipePaging?() ?? false)
           }) {
            return
        }

        guard let pressedIndexPath else { return }

        if dragState == .active {
            onDragMoved?(point)
            return
        }

        if dragState == .possible {
            let distance = hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y)
            if distance >= Self.dragActivationDistance {
                if onDragCandidate?(pressedIndexPath) ?? true {
                    dragState = .active
                    onDragBegan?(pressedIndexPath, dragStartPoint)
                    return
                }
                // Not draggable: fall back to plain click mode.
                dragState = .idle
            }
        }

        updatePressedAppearance(isInsideOriginalItem: indexPathForItem(at: point) == pressedIndexPath)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // An activated swipe reports its release through the tracker's `onEnded`.
        if swipeTracker.isActive {
            concludeSwipeTracking()
            return
        }

        let wasDragging = dragState == .active
        dragState = .idle

        let releasedIndexPath = indexPathForItem(at: point)
        let originalIndexPath = pressedIndexPath
        let wasBackgroundPress = pressedOnBackground

        // After a drag, the pressed item's cell is the hidden origin cell managed by the grid;
        // restoring its pressed alpha here would flash the old arrangement at the old position.
        if !wasDragging {
            updatePressedAppearance(isInsideOriginalItem: false)
        }
        pressedIndexPath = nil
        pressedOnBackground = false

        if wasDragging {
            onDragEnded?(point)
            return
        }

        // Match web click semantics: mouse-down and mouse-up must land on the same item.
        if let originalIndexPath, releasedIndexPath == originalIndexPath {
            onActivateItem?(originalIndexPath)
        } else if wasBackgroundPress, releasedIndexPath == nil {
            onBackgroundClick?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // An arrangement drag or swipe owns the pointer until it ends.
        guard dragState != .active, !swipeTracker.isActive else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: point) else { return nil }
        return onContextMenu?(indexPath)
    }

    /// Whether a swipe gesture started in this view is still tracking.
    var isSwipeTracking: Bool { swipeTracker.isActive }

    /// True while the swipe pager stands in for this view's content. The view must stay
    /// visible to AppKit — hiding the view that received mouse-down severs drag and mouse-up
    /// delivery entirely, wedging the gesture — so it disappears through alpha and stops
    /// hit-testing instead.
    var isSwipeStandby = false {
        didSet {
            guard isSwipeStandby != oldValue else { return }
            alphaValue = isSwipeStandby ? 0 : 1
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isSwipeStandby ? nil : super.hitTest(point)
    }

    /// Feeds a drag event that arrived through the responder chain. The pager puts this view
    /// on standby, so AppKit may re-route later events to the grid instead of here.
    func forwardSwipeDrag(_ point: NSPoint, timestamp: TimeInterval) {
        guard swipeTracker.isActive else { return }
        _ = swipeTracker.drag(to: point, timestamp: timestamp) { true }
    }

    /// Finishes an active swipe from a responder-chain mouse-up, reporting the release through
    /// the regular `onSwipeEnded` callback.
    func concludeSwipeTracking() {
        guard swipeTracker.isActive else { return }
        _ = swipeTracker.end()
        dragState = .idle
        pressedIndexPath = nil
        pressedOnBackground = false
    }

    /// Cancels every paging recognizer owned by the collection view. Content reloads call this
    /// even when no icon arrangement drag exists, so an old mouse or wheel gesture cannot rebuild
    /// a pager over replacement data.
    func cancelSwipeTracking() {
        swipeTracker.cancel()
        wheelSwipe.restart()
        ignoresWheelSwipeUntilBegan = true
    }

    /// Abandons an in-progress drag without reporting an end point. Used when a content reload
    /// invalidates the dragged cell; the trailing mouse-up is swallowed so it cannot fall
    /// through to background-click dismissal.
    func cancelDragGesture() {
        dragState = .idle
        pressedIndexPath = nil
        pressedOnBackground = false
        cancelSwipeTracking()
    }

    private func updatePressedAppearance(isInsideOriginalItem: Bool) {
        guard let pressedIndexPath, let item = item(at: pressedIndexPath) else { return }
        item.view.alphaValue = isInsideOriginalItem ? 0.72 : 1.0
    }

    override func scrollWheel(with event: NSEvent) {
        // Two-finger input must not page while an icon is being arranged or dragged.
        guard dragState != .active, !swipeTracker.isActive else { return }
        // Momentum follows a finger lift; the release decision and settle already carry it.
        guard event.momentumPhase.isEmpty else { return }

        if event.phase.isEmpty {
            handleDiscreteWheel(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                hasPreciseDeltas: event.hasPreciseScrollingDeltas,
                timestamp: event.timestamp
            )
            return
        }
        handleTrackpadWheel(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            phase: event.phase,
            timestamp: event.timestamp
        )
    }

    /// Notched mouse wheels and other phase-less input page discretely, at most one page per
    /// 0.45 seconds. Most mice only scroll vertically, so a vertical wheel pages as well; the
    /// dominant axis decides. Line-based deltas count notches, so a single notch turns a page,
    /// while precise deltas accumulate 24 points first. Internal so tests can drive it directly.
    func handleDiscreteWheel(
        deltaX: CGFloat,
        deltaY: CGFloat,
        hasPreciseDeltas: Bool,
        timestamp: TimeInterval
    ) {
        let delta = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
        guard abs(delta) > 0 else { return }

        accumulatedWheelDelta += delta
        let threshold: CGFloat = hasPreciseDeltas ? 24 : 1
        let canTurn = timestamp - lastDiscreteWheelTurnAt > 0.45
        if canTurn, abs(accumulatedWheelDelta) >= threshold {
            // Scrolling toward earlier content (positive deltas, in the user's scroll direction)
            // shows the previous page; scrolling toward later content shows the next page.
            onPageDelta?(accumulatedWheelDelta > 0 ? -1 : 1)
            lastDiscreteWheelTurnAt = timestamp
            accumulatedWheelDelta = 0
        }
    }

    /// Trackpad two-finger swipes drive the finger-following pager: translation follows the
    /// fingers and the release commits or snaps back. Internal (not private) so interaction
    /// tests can drive phases without synthesizing phase-bearing scroll events.
    func handleTrackpadWheel(
        deltaX: CGFloat,
        deltaY: CGFloat,
        phase: NSEvent.Phase,
        timestamp: TimeInterval
    ) {
        if phase.contains(.began) {
            ignoresWheelSwipeUntilBegan = false
            onSwipeGestureWillBegin?()
            wheelSwipe.restart()
        } else if ignoresWheelSwipeUntilBegan {
            return
        }
        if phase.contains(.cancelled) {
            // A system-cancelled gesture releases in place rather than deciding a page turn.
            if wheelSwipe.isActive {
                onSwipeEnded?(0, 0)
                wheelSwipe.restart()
            }
            return
        }
        if phase.contains(.ended) {
            if let release = wheelSwipe.finish(deltaX: deltaX, timestamp: timestamp) {
                onSwipeEnded?(release.translation, release.velocity)
            }
            return
        }
        if let translation = wheelSwipe.advance(
            deltaX: deltaX,
            deltaY: deltaY,
            timestamp: timestamp,
            canActivate: { [weak self] in
                // A wheel swipe must not take over while an icon arrangement drag could start.
                self?.pressedIndexPath == nil && (self?.onSwipePaging?() ?? false)
            }
        ) {
            onSwipeMoved?(translation)
        }
    }
}
