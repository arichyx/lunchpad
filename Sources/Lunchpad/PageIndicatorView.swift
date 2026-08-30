import AppKit

/// A 9-point visual dot with a 22-point hit target for reliable, non-overlapping clicks.
final class PageDotButton: NSButton {
    var isCurrentPage = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let diameter: CGFloat = 9
        let dotRect = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let baseAlpha: CGFloat = isCurrentPage ? 0.92 : 0.35
        NSColor.white.withAlphaComponent(isHighlighted ? baseAlpha * 0.7 : baseAlpha).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }
}

/// Classic Lunchpad-style page indicator dots.
final class PageIndicatorView: NSView {
    var onSelectPage: ((Int) -> Void)?

    private let stackView = NSStackView()
    private var displayedPageCount = 0

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: max(22, CGFloat(displayedPageCount) * 22),
            height: 22
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        // Each dot owns an independent, non-overlapping 22-point hit target.
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(pageCount: Int, currentPage: Int) {
        displayedPageCount = pageCount
        invalidateIntrinsicContentSize()

        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        isHidden = pageCount <= 1
        guard pageCount > 1 else { return }

        for page in 0..<pageCount {
            let button = PageDotButton()
            button.tag = page
            button.isCurrentPage = page == currentPage
            button.target = self
            button.action = #selector(selectPage(_:))
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22),
            ])
            stackView.addArrangedSubview(button)
        }
    }

    @objc private func selectPage(_ sender: NSButton) {
        onSelectPage?(sender.tag)
    }
}
