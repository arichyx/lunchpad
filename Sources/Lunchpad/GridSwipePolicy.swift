import AppKit

/// Decision rules for finger-following swipe paging on the launcher grid.
enum GridSwipePolicy {
    /// Background-press travel before the gesture is treated as a swipe rather than a click.
    static let activationDistance: CGFloat = 12
    /// Release translation, as a fraction of the pager width, that commits a page turn.
    static let commitFraction: CGFloat = 0.18
    /// Release velocity (points per second) that commits a page turn regardless of distance.
    static let commitVelocity: CGFloat = 550
    /// Damping applied once the translation pushes past the first or last page.
    static let rubberBandDamping: CGFloat = 0.35

    /// A swipe must move horizontally and travel far enough that it can no longer read as a click.
    static func shouldActivate(dx: CGFloat, dy: CGFloat) -> Bool {
        hypot(dx, dy) >= activationDistance && abs(dx) > abs(dy)
    }

    /// The translation to display for a raw drag delta, rubber-banded when no neighbor page exists.
    static func displayTranslation(raw: CGFloat, hasNeighbor: Bool) -> CGFloat {
        hasNeighbor ? raw : raw * rubberBandDamping
    }

    /// The page delta (-1, 1) to commit on release, or 0 to snap back in place. A fling whose
    /// velocity alone crosses the threshold dominates the slower distance decision.
    static func commitDirection(translation: CGFloat, velocity: CGFloat, pagerWidth: CGFloat) -> Int {
        let distanceCommit = abs(translation) >= pagerWidth * commitFraction
        let velocityCommit = abs(velocity) >= commitVelocity
        guard distanceCommit || velocityCommit else { return 0 }
        let dominant = velocityCommit ? velocity : translation
        return dominant > 0 ? -1 : 1
    }
}

/// Tracks one click-drag swipe gesture and reports finger-following translation plus a smoothed
/// release velocity. Used by both the grid collection view and the outer background.
final class GridSwipeTracker {
    var onMoved: ((CGFloat) -> Void)?
    var onEnded: ((_ translation: CGFloat, _ velocity: CGFloat) -> Void)?

    private(set) var isActive = false
    /// True from mouse-down until either end or cancellation. `isActive` alone is insufficient:
    /// a cancelled, not-yet-activated tracker must also reject trailing drag events until a new
    /// mouse-down supplies a fresh start point.
    private var isTracking = false
    private var startPoint = NSPoint.zero
    private var lastX: CGFloat = 0
    private var lastTimestamp: TimeInterval = 0
    private var velocity: CGFloat = 0

    /// `timestamp` comes from `NSEvent.timestamp` (seconds since boot); 0 is treated as unknown.
    func begin(at point: NSPoint) {
        isActive = false
        isTracking = true
        startPoint = point
        lastX = point.x
        lastTimestamp = 0
        velocity = 0
    }

    /// Feeds a drag movement. Returns `true` when the movement was consumed by an active or
    /// newly activated swipe, in which case the caller must not treat it further (as a click or
    /// an icon arrangement drag).
    func drag(to point: NSPoint, timestamp: TimeInterval, canActivate: () -> Bool) -> Bool {
        guard isTracking else { return false }
        if !isActive {
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            guard GridSwipePolicy.shouldActivate(dx: dx, dy: dy), canActivate() else { return false }
            isActive = true
        }
        if lastTimestamp > 0, timestamp > lastTimestamp {
            // Exponentially smoothed instantaneous velocity, robust to single jittery events.
            let dt = max(timestamp - lastTimestamp, 1.0 / 120)
            velocity = velocity * 0.6 + (point.x - lastX) / dt * 0.4
        }
        lastX = point.x
        lastTimestamp = timestamp
        onMoved?(point.x - startPoint.x)
        return true
    }

    /// Finishes the gesture, reporting total translation and velocity through `onEnded` (and
    /// returning them), or `nil` when no swipe ever activated (the press stays eligible for
    /// normal click handling).
    @discardableResult
    func end() -> (translation: CGFloat, velocity: CGFloat)? {
        guard isTracking else { return nil }
        isTracking = false
        guard isActive else { return nil }
        isActive = false
        let translation = lastX - startPoint.x
        onEnded?(translation, velocity)
        return (translation, velocity)
    }

    /// Abandons an active swipe without reporting a release. Callers follow up with a content
    /// reload whose `cancelSwipePaging` tears the pager down, so committing a page turn here —
    /// or animating a snap-back onto replaced content — would both be wrong.
    func cancel() {
        isTracking = false
        isActive = false
    }
}

/// Continuous two-finger trackpad swipe accumulator for finger-following wheel paging. The
/// discrete notched wheel keeps its own handling; this drives the same pager the mouse drag uses.
struct GridSwipeWheelTracker {
    /// Travel before the gesture takes over the pager, matching the mouse swipe.
    static let activationDistance: CGFloat = 12

    private(set) var translation: CGFloat = 0
    private(set) var isActive = false
    private(set) var velocity: CGFloat = 0
    private var lastTimestamp: TimeInterval = 0

    /// A new gesture (scroll phase `.began`) restarts accumulation.
    mutating func restart() {
        translation = 0
        velocity = 0
        lastTimestamp = 0
        isActive = false
    }

    /// Accumulates one movement sample. Returns the pager translation while the gesture is (or
    /// just became) active, or `nil` while it is still too small or too vertical to page.
    mutating func advance(
        deltaX: CGFloat,
        deltaY: CGFloat,
        timestamp: TimeInterval,
        canActivate: () -> Bool
    ) -> CGFloat? {
        translation += deltaX
        if lastTimestamp > 0, timestamp > lastTimestamp {
            // Exponential smoothing, matching the mouse tracker's release-velocity estimate.
            let dt = max(timestamp - lastTimestamp, 1.0 / 120)
            velocity = velocity * 0.6 + deltaX / dt * 0.4
        }
        lastTimestamp = timestamp

        if !isActive {
            guard abs(translation) >= Self.activationDistance,
                  abs(deltaX) > abs(deltaY),
                  canActivate()
            else { return nil }
            isActive = true
        }
        return translation
    }

    /// Final sample plus release decision input, or `nil` when the pager never activated. A
    /// sub-threshold gesture must not activate merely by ending.
    mutating func finish(deltaX: CGFloat, timestamp: TimeInterval) -> (translation: CGFloat, velocity: CGFloat)? {
        guard isActive else {
            restart()
            return nil
        }
        translation += deltaX
        let result = (translation, velocity)
        restart()
        return result
    }
}
