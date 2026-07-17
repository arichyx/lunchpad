import AppKit
import CoreGraphics
import QuartzCore

private let lunchpadMenuBarCoverColor = NSColor(
    calibratedRed: 0.05,
    green: 0.07,
    blue: 0.10,
    alpha: 1
)

/// The full-screen blurred backdrop. It stays below the Dock and ignores mouse input.
final class LunchpadBackdropWindow: NSWindow {
    let effectView = NSVisualEffectView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none

        effectView.material = .fullScreenUI
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .darkAqua)
        contentView = effectView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A top mask for the interaction window that covers the menu bar and fades into the backdrop.
final class MenuBarGradientView: NSView {
    private let gradientLayer = CAGradientLayer()
    var referenceHeight: CGFloat? {
        didSet { needsLayout = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradientLayer.colors = [
            lunchpadMenuBarCoverColor.cgColor,
            lunchpadMenuBarCoverColor.cgColor,
            lunchpadMenuBarCoverColor.withAlphaComponent(0).cgColor,
        ]
        gradientLayer.locations = [0, 0.30, 1]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(gradientLayer)
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        // The corner window renders the matching top slice of the full-height gradient.
        let height = max(bounds.height, referenceHeight ?? bounds.height)
        gradientLayer.frame = NSRect(
            x: bounds.minX,
            y: bounds.maxY - height,
            width: bounds.width,
            height: height
        )
    }

    // The visual layer ignores hit testing; the transparent interaction layer handles empty clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Fills the menu-bar corner above a vertical Dock without intercepting interaction.
final class MenuBarDockCornerWindow: NSWindow {
    let gradientView = MenuBarGradientView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none
        contentView = gradientView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lunchpad's full-screen, borderless, blurred interaction window.
/// Escape, empty-space clicks, and app launches hide it while monitors remain resident.
final class LunchpadWindow: NSWindow {
    private let rootView = NSView()
    private let backdropWindow = LunchpadBackdropWindow()
    private let menuBarGradientView = MenuBarGradientView()
    private let menuBarDockCornerWindow = MenuBarDockCornerWindow()
    private let gridView: IconGridView
    private let rootPageStore: RootPageStore
    private var isAnimatingClose = false
    private var presentationGeneration = 0
    private var menuBarGradientHeightConstraint: NSLayoutConstraint!

    init(items: [LunchpadItem], localizer: AppLocalizer, rootPageStore: RootPageStore) {
        gridView = IconGridView(items: items, localizer: localizer)
        self.rootPageStore = rootPageStore
        super.init(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // One continuous window covers both the application area and menu bar to avoid a seam.
        // It does not enter the Dock region, so the Dock remains visible and interactive.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // The high-level window hosts interaction and icons; the backdrop is a separate
        // full-screen window below the Dock.
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        // Borderless windows may still receive the system scale transition unless disabled.
        animationBehavior = .none

        rootView.wantsLayer = true
        // A fully transparent window is not a scroll hit target. One-percent black creates an
        // event surface without visible impact and prevents WindowServer from forwarding scrolls.
        rootView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor

        menuBarGradientView.translatesAutoresizingMaskIntoConstraints = false
        gridView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(menuBarGradientView)
        rootView.addSubview(gridView)

        // Every close path hides the reusable window instead of destroying it.
        gridView.onLaunch = { [weak self] in
            self?.close()
        }
        gridView.onBackgroundClick = { [weak self] in
            self?.close()
        }
        contentView = rootView

        menuBarGradientHeightConstraint = menuBarGradientView.heightAnchor.constraint(
            equalToConstant: 112
        )
        NSLayoutConstraint.activate([
            menuBarGradientView.topAnchor.constraint(equalTo: rootView.topAnchor),
            menuBarGradientView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            menuBarGradientView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            menuBarGradientHeightConstraint,

            gridView.topAnchor.constraint(equalTo: rootView.topAnchor),
            gridView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
        ])

    }

    func show() {
        if let screen = NSScreen.main {
            let contentFrame = presentationFrame(for: screen)
            setFrame(contentFrame, display: true)
            backdropWindow.setFrame(screen.frame, display: true)
            if let cornerFrame = menuBarDockCornerFrame(
                for: screen,
                contentFrame: contentFrame
            ) {
                menuBarDockCornerWindow.setFrame(cornerFrame, display: true)
            } else {
                menuBarDockCornerWindow.orderOut(nil)
                menuBarDockCornerWindow.setFrame(.zero, display: false)
            }
            let insets = contentInsets(for: screen, contentFrame: contentFrame)
            menuBarGradientHeightConstraint.constant = max(96, insets.top + 72)
            menuBarDockCornerWindow.gradientView.referenceHeight =
                menuBarGradientHeightConstraint.constant
            gridView.updateScreenInsets(insets, availableHeight: contentFrame.height)
        }
        let restoredRootPage = rootPageStore.restoredPage(
            availablePageCount: gridView.rootPageCount
        )
        gridView.prepareForPresentation(restoredRootPage: restoredRootPage)
        isAnimatingClose = false
        presentationGeneration &+= 1
        let generation = presentationGeneration
        alphaValue = 1
        backdropWindow.alphaValue = 0
        menuBarDockCornerWindow.alphaValue = 0
        menuBarGradientView.alphaValue = 0
        gridView.alphaValue = 0
        backdropWindow.orderFrontRegardless()
        if !menuBarDockCornerWindow.frame.isEmpty {
            menuBarDockCornerWindow.orderFrontRegardless()
        }
        makeKeyAndOrderFront(nil)
        rootView.layoutSubtreeIfNeeded()

        // Commit the complete alpha-zero state before starting a fixed-duration fade next turn.
        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                self.isVisible,
                !self.isAnimatingClose,
                self.presentationGeneration == generation
            else {
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.42
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.backdropWindow.animator().alphaValue = 1
                self.menuBarDockCornerWindow.animator().alphaValue = 1
                self.menuBarGradientView.animator().alphaValue = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                guard
                    let self,
                    self.isVisible,
                    !self.isAnimatingClose,
                    self.presentationGeneration == generation
                else {
                    return
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.30
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.gridView.animator().alphaValue = 1
                }
            }
        }
    }

    func update(
        items: [LunchpadItem],
        catalogChanged: Bool,
        invalidatedIconPaths: Set<String>?
    ) {
        gridView.updateItems(
            items,
            animated: catalogChanged && isVisible && !isAnimatingClose,
            invalidatedIconPaths: invalidatedIconPaths
        )
    }

    func refreshLocalizedContent() {
        gridView.refreshLocalizedContent()
    }

    override func close() {
        guard isVisible, !isAnimatingClose else { return }
        rootPageStore.save(page: gridView.rootPageForPersistence)
        isAnimatingClose = true
        presentationGeneration &+= 1

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            gridView.animator().alphaValue = 0
        }

        // Keep the backdrop full-screen during exit and animate opacity only.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            backdropWindow.animator().alphaValue = 0
            menuBarDockCornerWindow.animator().alphaValue = 0
            menuBarGradientView.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.orderOut(nil)
                self.backdropWindow.orderOut(nil)
                self.menuBarDockCornerWindow.orderOut(nil)
                self.backdropWindow.alphaValue = 1
                self.menuBarDockCornerWindow.alphaValue = 1
                self.menuBarGradientView.alphaValue = 1
                self.gridView.alphaValue = 1
                self.isAnimatingClose = false
            }
        }
    }

    private func contentInsets(for screen: NSScreen, contentFrame: NSRect) -> NSEdgeInsets {
        let visibleFrame = screen.visibleFrame
        let safeArea = screen.safeAreaInsets

        return NSEdgeInsets(
            top: max(safeArea.top, contentFrame.maxY - visibleFrame.maxY),
            left: max(safeArea.left, visibleFrame.minX - contentFrame.minX),
            bottom: max(safeArea.bottom, visibleFrame.minY - contentFrame.minY),
            right: max(safeArea.right, contentFrame.maxX - visibleFrame.maxX)
        )
    }

    private func presentationFrame(for screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        let bottomInset = max(0, visibleFrame.minY - frame.minY)
        let leftInset = max(0, visibleFrame.minX - frame.minX)
        let rightInset = max(0, frame.maxX - visibleFrame.maxX)
        let largestInset = max(bottomInset, leftInset, rightInset)

        guard largestInset > 0 else {
            return frame
        }

        if bottomInset == largestInset {
            return NSRect(
                x: frame.minX,
                y: frame.minY + bottomInset,
                width: frame.width,
                height: frame.height - bottomInset
            )
        }

        if leftInset == largestInset {
            return NSRect(
                x: frame.minX + leftInset,
                y: frame.minY,
                width: frame.width - leftInset,
                height: frame.height
            )
        }

        return NSRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width - rightInset,
            height: frame.height
        )
    }

    private func menuBarDockCornerFrame(
        for screen: NSScreen,
        contentFrame: NSRect
    ) -> NSRect? {
        let screenFrame = screen.frame
        let menuBarHeight = max(
            screen.safeAreaInsets.top,
            screenFrame.maxY - screen.visibleFrame.maxY
        )
        guard menuBarHeight > 0 else { return nil }

        // A vertical Dock leaves roughly half a menu-bar height above its rounded container.
        // Extend the corner window through that gap using the same gradient.
        let sideDockTopGap = max(14, min(28, menuBarHeight * 0.5))
        let cornerHeight = menuBarHeight + sideDockTopGap

        let leftDockWidth = max(0, contentFrame.minX - screenFrame.minX)
        let rightDockWidth = max(0, screenFrame.maxX - contentFrame.maxX)

        if rightDockWidth > 0 {
            return NSRect(
                x: contentFrame.maxX,
                y: screenFrame.maxY - cornerHeight,
                width: rightDockWidth,
                height: cornerHeight
            )
        }

        if leftDockWidth > 0 {
            return NSRect(
                x: screenFrame.minX,
                y: screenFrame.maxY - cornerHeight,
                width: leftDockWidth,
                height: cornerHeight
            )
        }

        return nil
    }

    // Borderless windows cannot become key by default; override this to receive Escape.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Consumes all scroll events at the window boundary: horizontal pages, vertical is discarded.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel else {
            super.sendEvent(event)
            return
        }
        gridView.handleScrollWheel(event)
    }

    // Escape (key code 53) closes the current level or window.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            if !gridView.dismissOpenFolder() {
                close()
            }
        } else if event.keyCode == 123 {
            gridView.showPreviousPage()
        } else if event.keyCode == 124 {
            gridView.showNextPage()
        } else {
            super.keyDown(with: event)
        }
    }
}
