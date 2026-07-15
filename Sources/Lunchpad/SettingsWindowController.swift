import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private enum Feedback {
        case key(String)
        case formatted(String, String)
    }

    private let preferences: LunchpadPreferences
    private let localizer: AppLocalizer
    private let hotKeyController: HotKeyController
    private let loginItemController: LoginItemController
    private let gestureErrorProvider: () -> String?

    private let appearanceTitle = NSTextField(labelWithString: "")
    private let activationTitle = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let orderLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let loginItemLabel = NSTextField(labelWithString: "")
    private let gestureLabel = NSTextField(labelWithString: "")
    private let languagePopup = NSPopUpButton()
    private let orderPopup = NSPopUpButton()
    private let shortcutRecorder: ShortcutRecorderView
    private let clearShortcutButton = NSButton()
    private let loginItemSwitch = NSSwitch()
    private let gestureSwitch = NSSwitch()
    private let feedbackLabel = NSTextField(wrappingLabelWithString: "")
    private var transientFeedback: Feedback?

    init(
        preferences: LunchpadPreferences,
        localizer: AppLocalizer,
        hotKeyController: HotKeyController,
        loginItemController: LoginItemController,
        gestureErrorProvider: @escaping () -> String?
    ) {
        self.preferences = preferences
        self.localizer = localizer
        self.hotKeyController = hotKeyController
        self.loginItemController = loginItemController
        self.gestureErrorProvider = gestureErrorProvider
        shortcutRecorder = ShortcutRecorderView(localizer: localizer)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        super.init(window: window)
        setupContent()
        refreshLocalizedContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        refreshLocalizedContent()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshLocalizedContent() {
        window?.title = localizer.string("settings.title")
        appearanceTitle.stringValue = localizer.string("settings.appearance")
        activationTitle.stringValue = localizer.string("settings.activation")
        languageLabel.stringValue = localizer.string("settings.language")
        orderLabel.stringValue = localizer.string("settings.application-order")
        shortcutLabel.stringValue = localizer.string("settings.shortcut")
        loginItemLabel.stringValue = localizer.string("settings.launch-at-login")
        gestureLabel.stringValue = localizer.string("settings.four-finger-pinch")
        clearShortcutButton.title = localizer.string("settings.shortcut.clear")

        rebuildLanguagePopup()
        rebuildOrderPopup()
        refreshShortcutState()
        loginItemSwitch.isEnabled = loginItemController.isAvailable
        loginItemSwitch.state = loginItemController.isEnabled ? .on : .off
        gestureSwitch.state = preferences.fourFingerPinchEnabled ? .on : .off
        refreshFeedback()
    }

    private func setupContent() {
        guard let window else { return }
        let content = NSView()
        window.contentView = content

        configureSectionTitle(appearanceTitle)
        configureSectionTitle(activationTitle)
        [languageLabel, orderLabel, shortcutLabel, loginItemLabel, gestureLabel].forEach {
            $0.alignment = .right
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.widthAnchor.constraint(equalToConstant: 150).isActive = true
        }

        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        orderPopup.target = self
        orderPopup.action = #selector(orderChanged(_:))

        shortcutRecorder.onCandidate = { [weak self] configuration in
            self?.applyShortcut(.configured(configuration))
        }
        shortcutRecorder.onClear = { [weak self] in
            self?.applyShortcut(.disabled)
        }
        shortcutRecorder.onValidationError = { [weak self] in
            self?.transientFeedback = .key("settings.shortcut.invalid")
            self?.refreshFeedback()
        }

        clearShortcutButton.bezelStyle = .rounded
        clearShortcutButton.target = self
        clearShortcutButton.action = #selector(clearShortcut(_:))

        loginItemSwitch.target = self
        loginItemSwitch.action = #selector(loginItemChanged(_:))
        gestureSwitch.target = self
        gestureSwitch.action = #selector(gestureChanged(_:))

        feedbackLabel.textColor = .secondaryLabelColor
        feedbackLabel.font = .systemFont(ofSize: 12)
        feedbackLabel.maximumNumberOfLines = 3

        let shortcutControls = NSStackView(views: [shortcutRecorder, clearShortcutButton])
        shortcutControls.orientation = .horizontal
        shortcutControls.alignment = .centerY
        shortcutControls.spacing = 8

        let stack = NSStackView(views: [
            appearanceTitle,
            makeRow(label: languageLabel, control: languagePopup),
            makeRow(label: orderLabel, control: orderPopup),
            activationTitle,
            makeRow(label: shortcutLabel, control: shortcutControls),
            makeRow(label: loginItemLabel, control: loginItemSwitch),
            makeRow(label: gestureLabel, control: gestureSwitch),
            feedbackLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        languagePopup.widthAnchor.constraint(equalToConstant: 230).isActive = true
        orderPopup.widthAnchor.constraint(equalToConstant: 230).isActive = true
        feedbackLabel.widthAnchor.constraint(equalToConstant: 490).isActive = true

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -34),
        ])
    }

    private func configureSectionTitle(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
    }

    private func makeRow(label: NSTextField, control: NSView) -> NSStackView {
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        return row
    }

    private func rebuildLanguagePopup() {
        languagePopup.removeAllItems()
        let values: [(InterfaceLanguage, String)] = [
            (.system, localizer.string("settings.language.system")),
            (.english, localizer.string("settings.language.english")),
            (.simplifiedChinese, localizer.string("settings.language.simplified-chinese")),
        ]
        for (index, value) in values.enumerated() {
            languagePopup.addItem(withTitle: value.1)
            languagePopup.item(at: index)?.representedObject = value.0.rawValue
        }
        let index = values.firstIndex { $0.0 == preferences.interfaceLanguage } ?? 0
        languagePopup.selectItem(at: index)
    }

    private func rebuildOrderPopup() {
        orderPopup.removeAllItems()
        let values: [(ApplicationSortOrder, String)] = [
            (.name, localizer.string("settings.application-order.name")),
            (.creationDate, localizer.string("settings.application-order.creation-date")),
            (.modificationDate, localizer.string("settings.application-order.modification-date")),
        ]
        for (index, value) in values.enumerated() {
            orderPopup.addItem(withTitle: value.1)
            orderPopup.item(at: index)?.representedObject = value.0.rawValue
        }
        let index = values.firstIndex { $0.0 == preferences.applicationSortOrder } ?? 0
        orderPopup.selectItem(at: index)
    }

    private func refreshShortcutState() {
        let managed = hotKeyController.isExternallyManaged
        shortcutRecorder.configuration = managed
            ? hotKeyController.activeConfiguration
            : preferences.hotKey.configuration
        shortcutRecorder.isEditable = !managed
        shortcutRecorder.refreshLocalizedContent(localizer)
        clearShortcutButton.isEnabled = !managed && preferences.hotKey.configuration != nil
    }

    private func applyShortcut(_ preference: HotKeyPreference) {
        switch hotKeyController.apply(preference) {
        case .success:
            preferences.hotKey = preference
            transientFeedback = nil
        case .failure(let error):
            switch error {
            case .conflict:
                transientFeedback = .key("settings.shortcut.conflict")
            case .invalid:
                transientFeedback = .key("settings.shortcut.invalid")
            case .managedByEnvironment:
                transientFeedback = nil
            case .unavailable:
                transientFeedback = .key("settings.shortcut.unavailable")
            }
        }
        refreshShortcutState()
        refreshFeedback()
    }

    private func refreshFeedback() {
        let feedback: Feedback?
        if let override = hotKeyController.environmentOverride {
            feedback = .formatted("settings.shortcut.override", override.rawValue)
        } else if let transientFeedback {
            feedback = transientFeedback
        } else if hotKeyController.lastError != nil {
            feedback = .key("settings.shortcut.unavailable")
        } else if let gestureError = gestureErrorProvider() {
            feedback = .formatted("settings.four-finger-pinch.unavailable", gestureError)
        } else if !loginItemController.isAvailable {
            feedback = .key("settings.launch-at-login.development")
        } else {
            feedback = nil
        }

        switch feedback {
        case .key(let key):
            feedbackLabel.stringValue = localizer.string(key)
        case .formatted(let key, let argument):
            feedbackLabel.stringValue = localizer.formatted(key, argument)
        case nil:
            feedbackLabel.stringValue = ""
        }
        feedbackLabel.isHidden = feedback == nil
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let language = InterfaceLanguage(rawValue: rawValue) else { return }
        preferences.interfaceLanguage = language
    }

    @objc private func orderChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let order = ApplicationSortOrder(rawValue: rawValue) else { return }
        preferences.applicationSortOrder = order
    }

    @objc private func clearShortcut(_ sender: Any?) {
        applyShortcut(.disabled)
    }

    @objc private func loginItemChanged(_ sender: NSSwitch) {
        let requested = sender.state == .on
        switch loginItemController.setEnabled(requested) {
        case .success(let actual):
            sender.state = actual ? .on : .off
            transientFeedback = nil
        case .failure(let error):
            sender.state = loginItemController.isEnabled ? .on : .off
            transientFeedback = .formatted(
                "settings.launch-at-login.error",
                error.localizedDescription
            )
        }
        refreshFeedback()
    }

    @objc private func gestureChanged(_ sender: NSSwitch) {
        preferences.fourFingerPinchEnabled = sender.state == .on
        transientFeedback = nil
        refreshFeedback()
    }
}
