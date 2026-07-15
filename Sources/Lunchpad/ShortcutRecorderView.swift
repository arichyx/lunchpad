import AppKit
import Carbon.HIToolbox

@MainActor
final class ShortcutRecorderView: NSView {
    var onCandidate: ((HotKeyConfiguration) -> Void)?
    var onClear: (() -> Void)?
    var onValidationError: (() -> Void)?

    var configuration: HotKeyConfiguration? {
        didSet { refreshText() }
    }
    var isEditable = true {
        didSet {
            alphaValue = isEditable ? 1 : 0.62
            refreshAppearance()
        }
    }

    private let label = NSTextField(labelWithString: "")
    private var localizer: AppLocalizer
    private var isRecording = false

    init(localizer: AppLocalizer) {
        self.localizer = localizer
        super.init(frame: .zero)
        setup()
        refreshLocalizedContent(localizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { isEditable }

    override func mouseDown(with event: NSEvent) {
        guard isEditable else { return }
        window?.makeFirstResponder(self)
        isRecording = true
        refreshText()
        refreshAppearance()
    }

    override func keyDown(with event: NSEvent) {
        guard isEditable else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            refreshText()
            refreshAppearance()
            return
        }
        if event.keyCode == UInt16(kVK_Delete),
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            isRecording = false
            configuration = nil
            onClear?()
            refreshAppearance()
            return
        }
        guard let candidate = Self.configuration(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) else {
            onValidationError?()
            NSSound.beep()
            return
        }

        isRecording = false
        onCandidate?(candidate)
        refreshAppearance()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        refreshAppearance()
        return became
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        let resigned = super.resignFirstResponder()
        refreshText()
        refreshAppearance()
        return resigned
    }

    func refreshLocalizedContent(_ localizer: AppLocalizer) {
        self.localizer = localizer
        setAccessibilityLabel(localizer.string("settings.shortcut"))
        refreshText()
    }

    static func configuration(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> HotKeyConfiguration? {
        var modifiers: UInt32 = 0
        if modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let configuration = HotKeyConfiguration(
            keyCode: UInt32(keyCode),
            modifiers: modifiers
        )
        return configuration.isValid ? configuration : nil
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        refreshAppearance()
    }

    private func refreshText() {
        if isRecording {
            label.stringValue = localizer.string("settings.shortcut.recording")
        } else if let configuration {
            label.stringValue = configuration.displayName
        } else {
            label.stringValue = localizer.string("settings.shortcut.disabled")
        }
    }

    private func refreshAppearance() {
        let focused = window?.firstResponder === self
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = (focused ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        label.textColor = isEditable ? .labelColor : .secondaryLabelColor
    }
}
