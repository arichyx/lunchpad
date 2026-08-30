import AppKit

/// Translucent drop-target highlight shown during drag arrangement. It never intercepts input;
/// the collection view's own gesture tracking owns the mouse.
final class GridDragFeedbackView: NSView {
    enum Style {
        /// Subtle outline marking an insertion position, including empty slots.
        case insertionSlot
        /// Brighter bubble behind an item that would absorb the dragged icon.
        case mergeTarget
        /// Highlight behind the folder title marking removal back to the root level.
        case removalTarget
    }

    private let highlightLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        highlightLayer.cornerRadius = 18
        highlightLayer.cornerCurve = .continuous
        highlightLayer.borderWidth = 1
        layer?.addSublayer(highlightLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(style: Style, frame: NSRect) {
        switch style {
        case .insertionSlot:
            highlightLayer.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            highlightLayer.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
        case .mergeTarget:
            highlightLayer.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
            highlightLayer.borderColor = NSColor.white.withAlphaComponent(0.50).cgColor
        case .removalTarget:
            highlightLayer.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
            highlightLayer.borderColor = NSColor.white.withAlphaComponent(0.42).cgColor
        }
        self.frame = frame
        highlightLayer.frame = bounds
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}
