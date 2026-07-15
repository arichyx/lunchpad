import AppKit

/// A lightweight Apple Launchpad-style search field without NSSearchFieldCell's dark bezel.
final class LunchpadSearchField: NSView, NSTextFieldDelegate {
    var onTextChange: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onSubmit: (() -> Void)?

    private let searchIcon = NSImageView()
    private let textField = NSTextField()
    private let clearButton = NSButton()

    var stringValue: String {
        get { textField.stringValue }
        set {
            textField.stringValue = newValue
            clearButton.isHidden = newValue.isEmpty
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textField)
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        updateAppearance(isEditing: false)

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        searchIcon.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: "搜索"
        )?.withSymbolConfiguration(symbolConfiguration)
        searchIcon.contentTintColor = NSColor.white.withAlphaComponent(0.62)
        searchIcon.imageScaling = .scaleProportionallyDown
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchIcon)

        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 14, weight: .regular)
        textField.textColor = NSColor.white.withAlphaComponent(0.92)
        textField.placeholderAttributedString = NSAttributedString(
            string: "搜索",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.48),
                .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            ]
        )
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        clearButton.isBordered = false
        clearButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "清除搜索"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        clearButton.contentTintColor = NSColor.white.withAlphaComponent(0.48)
        clearButton.target = self
        clearButton.action = #selector(clearSearch)
        clearButton.isHidden = true
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            searchIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 14),
            searchIcon.heightAnchor.constraint(equalToConstant: 14),

            textField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 5),
            textField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 20),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func updateAppearance(isEditing: Bool) {
        layer?.backgroundColor = NSColor.black
            .withAlphaComponent(isEditing ? 0.13 : 0.08)
            .cgColor
        layer?.borderColor = NSColor.white
            .withAlphaComponent(isEditing ? 0.34 : 0.18)
            .cgColor
    }

    @objc private func clearSearch() {
        stringValue = ""
        onTextChange?("")
        window?.makeFirstResponder(textField)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        updateAppearance(isEditing: true)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        updateAppearance(isEditing: false)
    }

    func controlTextDidChange(_ obj: Notification) {
        clearButton.isHidden = textField.stringValue.isEmpty
        onTextChange?(textField.stringValue)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if stringValue.isEmpty {
                onCancel?()
            } else {
                clearSearch()
            }
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onSubmit?()
            return true
        }
        return false
    }
}
