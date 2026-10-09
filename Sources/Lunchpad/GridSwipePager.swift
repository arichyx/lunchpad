import AppKit
import QuartzCore

/// What the swipe pager needs from the grid that hosts it.
@MainActor
protocol GridSwipePagerHost: AnyObject {
    /// The view the pager covers; pages travel its full width.
    var swipeHostView: NSView { get }
    /// The real grid, which the pager stands in for while a swipe is on screen.
    var swipeCollectionView: LunchpadCollectionView { get }
    /// Whether the current content has more than one page.
    var isSwipePagingAllowed: Bool { get }
    var swipeMetrics: LunchpadGridMetrics { get }
    /// Items of the current page (offset 0) or of the previous (-1) or next (1) page; empty when
    /// that page does not exist.
    func swipePageItems(offset: Int) -> [LunchpadItem]
    /// A grid slot's frame in collection-view coordinates.
    func swipeSlotFrame(at slot: Int) -> NSRect
    /// The pager settled on a neighbor page; the host commits that page without another
    /// transition, because the pager already moved it into place.
    func swipePagerDidSettle(onPageOffset offset: Int)
}

/// The finger-following pager that replaces the collection view while a swipe is on screen.
///
/// A fixed clip view spanning the host holds a translating content view with static snapshots
/// of the current page and both existing neighbors. Pages travel the whole screen width like the
/// real Launchpad: each page snapshot keeps its own grid inset, so icons slide across the outer
/// margins instead of being cut at them. Moving the frame (not a layer transform) keeps AppKit's
/// managed layer geometry out of the way. Mouse drags and trackpad two-finger swipes drive the
/// same pager.
@MainActor
final class GridSwipePager {
    /// A plain container in the collection view's flipped coordinate space, so grid slot frames
    /// can be reused unchanged for the snapshot pages. It is transparent to hit testing: it is pure
    /// presentation, and letting it swallow events would wedge the launcher once a swipe hides the
    /// tracked collection view.
    final class PagerView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private weak var host: GridSwipePagerHost?
    private var clipView: PagerView?
    private var contentView: PagerView?
    /// Snapshot image views whose icons were uncached at build time, paired with their URLs so
    /// later movement events can repaint them as the background prewarm fills the cache.
    private var pendingIcons: [(imageView: NSImageView, url: URL)] = []
    /// Destination of the settle animation in progress, or nil while the fingers are down and
    /// while no pager is on screen. The host commits it before a new input begins so every gesture
    /// resolves against what the user can actually see.
    private(set) var settleDirection: Int?
    /// The current horizontal translation in points; 0 while no swipe is active.
    private(set) var translation: CGFloat = 0
    /// Invalidates a pending settle when the pager is rebuilt or torn down first.
    private var generation = 0

    init(host: GridSwipePagerHost) {
        self.host = host
    }

    /// Whether the pager is on screen.
    var isActive: Bool { clipView != nil }

    /// Whether a released swipe is still animating to its destination.
    var isSettling: Bool { settleDirection != nil }

    /// Follows the fingers. Dragging right (positive) reveals the previous page; dragging left
    /// reveals the next.
    func move(rawTranslation: CGFloat) {
        // A new gesture may arrive before the previous settle timer fires. Commit the page that
        // is already visually winning before interpreting this translation against its neighbors.
        finishSettleImmediately()
        // The host only changes whether paging is allowed alongside a reload, which always tears
        // down an in-flight swipe first, so it cannot go stale in the middle of a gesture.
        guard let host, host.isSwipePagingAllowed else { return }
        // A drag event re-engages the pager: a completion still pending from an earlier release
        // (quick successive swipes reuse the settling pager) must not fire now.
        generation += 1
        if clipView == nil {
            begin(host: host)
        }

        let direction = rawTranslation >= 0 ? -1 : 1
        let hasNeighbor = !host.swipePageItems(offset: direction).isEmpty
        var displayed = GridSwipePolicy.displayTranslation(
            raw: rawTranslation,
            hasNeighbor: hasNeighbor
        )
        if hasNeighbor {
            // Both pages are already on screen; never slide past the neighbor's far edge.
            let pageUnit = host.swipeHostView.bounds.width
            displayed = min(max(displayed, -pageUnit), pageUnit)
        }
        translation = displayed
        contentView?.frame.origin.x = displayed
        fillMissingIcons()
    }

    /// Settles on the neighbor the release committed to, or back on the current page.
    func end(velocity: CGFloat) {
        guard let host, let clipView, let contentView else { return }
        let pageUnit = host.swipeHostView.bounds.width
        var direction = GridSwipePolicy.commitDirection(
            translation: translation,
            velocity: velocity,
            pagerWidth: pageUnit
        )
        if host.swipePageItems(offset: direction).isEmpty {
            direction = 0
        }

        settleDirection = direction
        translation = 0
        let target: CGFloat = direction == 0 ? 0 : -CGFloat(direction) * pageUnit
        let duration = direction == 0 ? 0.25 : 0.22

        var settleFrame = contentView.frame
        settleFrame.origin.x = target
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            contentView.animator().frame = settleFrame
        }

        // Follow the drag-settle pattern: a delayed main-queue hop instead of a Core Animation
        // completion, which offscreen layers do not deliver reliably. The generation check
        // invalidates the swap-in when a rebuild or content reload tears the pager down first.
        let settleGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            guard let self, self.generation == settleGeneration else { return }
            // Use the retained clip identity to ensure an unrelated pager was not substituted
            // without also changing the generation.
            guard self.clipView === clipView else { return }
            self.completeSettle(direction: direction)
        }
    }

    /// Completes the visible settle immediately. Invoked before a fresh pointer or wheel gesture
    /// so quick successive swipes advance from the first swipe's destination instead of
    /// invalidating its delayed page commit.
    func finishSettleImmediately() {
        guard let direction = settleDirection else { return }
        generation += 1
        contentView?.layer?.removeAllAnimations()
        completeSettle(direction: direction)
    }

    /// Tears down an in-flight swipe instantly. Every content reload calls this, so the pager can
    /// never survive into a page or dataset it no longer represents.
    func cancel() {
        generation += 1
        settleDirection = nil
        tearDown()
    }

    private func begin(host: GridSwipePagerHost) {
        generation += 1
        settleDirection = nil
        pendingIcons.removeAll()
        let hostView = host.swipeHostView
        let collectionView = host.swipeCollectionView
        let bounds = hostView.bounds

        // The clip spans the whole host: pages travel the full screen width, and their icons pass
        // across the outer margins instead of vanishing at an invisible wall where the grid area
        // ends. Nothing can render past the screen edge.
        let clip = PagerView(frame: bounds)
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true

        // Each page snapshot keeps its grid inset inside its own full-width page unit; at rest the
        // current page's icons land exactly where the real collection view draws them. The y must
        // be flipped with the container: the host measures from the bottom, the flipped pager
        // content from the top.
        let pageUnit = bounds.width
        let pageFrame = CGRect(
            x: collectionView.frame.minX,
            y: bounds.height - collectionView.frame.maxY,
            width: collectionView.frame.width,
            height: collectionView.frame.height
        )
        let content = PagerView(frame: CGRect(origin: .zero, size: bounds.size))
        content.addSubview(
            makePageSnapshot(items: host.swipePageItems(offset: 0), frame: pageFrame, host: host)
        )
        for direction in [-1, 1] {
            let neighbor = host.swipePageItems(offset: direction)
            guard !neighbor.isEmpty else { continue }
            // Both neighbors are materialized up front: reversing a swipe mid-gesture must not
            // rebuild (and repaint) the pages the fingers are following.
            content.addSubview(
                makePageSnapshot(
                    items: neighbor,
                    frame: pageFrame.offsetBy(dx: CGFloat(direction) * pageUnit, dy: 0),
                    host: host
                )
            )
        }
        clip.addSubview(content)
        // Above the pages' stand-in view, below the page indicator so the dots stay visible.
        hostView.addSubview(clip, positioned: .above, relativeTo: collectionView)
        clipView = clip
        contentView = content
        // Standby rather than hidden: hidden views stop receiving the drag and mouse-up events
        // AppKit still owes the mouse-down view, which would strand the gesture mid-flight.
        collectionView.isSwipeStandby = true
    }

    private func completeSettle(direction: Int) {
        settleDirection = nil
        tearDown()
        if direction != 0 {
            host?.swipePagerDidSettle(onPageOffset: direction)
        }
    }

    private func tearDown() {
        clipView?.removeFromSuperview()
        clipView = nil
        contentView = nil
        pendingIcons.removeAll()
        host?.swipeCollectionView.isSwipeStandby = false
        translation = 0
    }

    /// Repaints snapshot icons whose images were still uncached when the pager was built. The
    /// background prewarm fills the cache on its own cadence; each movement event picks up
    /// whatever has become ready.
    private func fillMissingIcons() {
        guard !pendingIcons.isEmpty else { return }
        pendingIcons.removeAll { imageView, url in
            let image = AppIconCache.shared.cachedIcon(for: url)
            imageView.image = image
            return image != nil
        }
    }

    /// A static copy of one page in flipped grid coordinates: cached icons above their labels,
    /// laid out like an `AppIconCell`. Cheap enough to build at swipe start.
    private func makePageSnapshot(
        items: [LunchpadItem],
        frame: NSRect,
        host: GridSwipePagerHost
    ) -> NSView {
        let view = PagerView(frame: frame)
        for (slot, item) in items.enumerated() {
            view.addSubview(
                makeItemView(
                    for: item,
                    frame: host.swipeSlotFrame(at: slot),
                    metrics: host.swipeMetrics
                )
            )
        }
        return view
    }

    private func makeItemView(
        for item: LunchpadItem,
        frame: NSRect,
        metrics: LunchpadGridMetrics
    ) -> NSView {
        let container = PagerView(frame: frame)
        let iconSide = metrics.iconSide
        let iconFrame = NSRect(
            x: (frame.width - iconSide) / 2,
            y: 0,
            width: iconSide,
            height: iconSide
        )
        switch item {
        case .app(let app):
            let imageView = NSImageView(frame: iconFrame)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            // Never load synchronously here: a swipe may build over a hundred icons and a cold
            // cache would stall the main thread on Launch Services during the gesture. Misses are
            // queued for the background prewarm and repainted as they arrive.
            imageView.image = AppIconCache.shared.cachedIcon(for: app.url)
            if imageView.image == nil {
                pendingIcons.append((imageView, app.url))
            }
            container.addSubview(imageView)
        case .folder(let folder):
            let folderView = FolderIconView(frame: iconFrame)
            folderView.configureCached(with: Array(folder.apps.prefix(9)))
            container.addSubview(folderView)
        }

        container.addSubview(GridItemLabel.make(
            name: item.name,
            width: frame.width,
            originY: iconSide + metrics.labelSpacing,
            metrics: metrics
        ))
        return container
    }
}

/// The single-line name shown under icons in pager and drag snapshots.
@MainActor
enum GridItemLabel {
    static func make(
        name: String,
        width: CGFloat,
        originY: CGFloat,
        metrics: LunchpadGridMetrics
    ) -> NSTextField {
        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: metrics.labelFontSize, weight: .regular)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        // `AppIconCell` pins its label's alignment rect to the cell edges, and a text field's frame
        // extends past its alignment rect on both sides. Place the snapshot the same way so a name
        // that fits in the cell is not truncated while it is shown by a snapshot.
        label.frame = label.frame(forAlignmentRect: NSRect(
            x: 0,
            y: originY,
            width: width,
            height: ceil(metrics.labelFontSize * 1.34)
        ))
        return label
    }
}
