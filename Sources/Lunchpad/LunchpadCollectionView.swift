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

    private enum DragState {
        case idle
        case possible
        case active
    }

    private static let dragActivationDistance: CGFloat = 8

    private var dragState = DragState.idle
    private var dragStartPoint = NSPoint.zero
    private var accumulatedHorizontalDelta = 0.0
    private var didTurnPageInCurrentGesture = false
    private var lastDiscreteWheelTurnAt = 0.0
    private var pressedIndexPath: IndexPath?
    private var pressedOnBackground = false

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressedIndexPath = indexPathForItem(at: point)
        pressedOnBackground = pressedIndexPath == nil
        dragState = pressedIndexPath == nil ? .idle : .possible
        dragStartPoint = point
        updatePressedAppearance(isInsideOriginalItem: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressedIndexPath else { return }
        let point = convert(event.locationInWindow, from: nil)

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

    /// Abandons an in-progress drag without reporting an end point. Used when a content reload
    /// invalidates the dragged cell; the trailing mouse-up is swallowed so it cannot fall
    /// through to background-click dismissal.
    func cancelDragGesture() {
        dragState = .idle
        pressedIndexPath = nil
        pressedOnBackground = false
    }

    private func updatePressedAppearance(isInsideOriginalItem: Bool) {
        guard let pressedIndexPath, let item = item(at: pressedIndexPath) else { return }
        item.view.alphaValue = isInsideOriginalItem ? 0.72 : 1.0
    }

    override func scrollWheel(with event: NSEvent) {
        // Two-finger swipes must not page while an icon is being arranged.
        guard dragState != .active else { return }
        // Ignore momentum events so one gesture advances at most one page.
        guard event.momentumPhase.isEmpty else { return }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }

        if event.phase == .began {
            accumulatedHorizontalDelta = 0
            didTurnPageInCurrentGesture = false
        }
        accumulatedHorizontalDelta += event.scrollingDeltaX

        let now = ProcessInfo.processInfo.systemUptime
        let isDiscreteWheel = event.phase.isEmpty
        let canTurn = isDiscreteWheel
            ? now - lastDiscreteWheelTurnAt > 0.45
            : !didTurnPageInCurrentGesture

        if canTurn && abs(accumulatedHorizontalDelta) >= 24 {
            // Swiping left shows the next page; swiping right shows the previous page.
            onPageDelta?(accumulatedHorizontalDelta > 0 ? -1 : 1)
            didTurnPageInCurrentGesture = true
            lastDiscreteWheelTurnAt = now
            accumulatedHorizontalDelta = 0
        }

        if event.phase == .ended || event.phase == .cancelled {
            accumulatedHorizontalDelta = 0
        }
    }
}
