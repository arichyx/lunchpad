import AppKit

/// The open folder's title.
///
/// A renamable folder's title becomes editable when clicked. Return or leaving the field commits
/// a changed, non-empty name; Escape restores the previous name. System folders and the flat
/// fallback layout keep a read-only title.
final class FolderTitleField: NSTextField, NSTextFieldDelegate {
    /// Whether the presented folder may be renamed. Turning it off cancels an edit in progress.
    var isRenamable = false {
        didSet {
            if !isRenamable { cancelEditing() }
        }
    }

    /// Delivered with the trimmed name when an edit commits a change.
    var onRename: ((String) -> Void)?

    private var nameBeforeEditing: String?

    var isEditingName: Bool { nameBeforeEditing != nil }

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 22, weight: .medium)
        textColor = .white
        alignment = .center
        lineBreakMode = .byTruncatingTail
        cell?.usesSingleLineMode = true
        cell?.isScrollable = true
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Editable text fields report no intrinsic width, so measure the visible text directly.
    /// The field leaves room for the editing background and keeps a typing area while editing.
    override var intrinsicContentSize: NSSize {
        let text = currentEditor()?.string ?? stringValue
        let textWidth = (text as NSString).size(
            withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 22, weight: .medium)]
        ).width
        let minimumWidth: CGFloat = isEditingName ? 160 : 0
        return NSSize(
            width: max(minimumWidth, ceil(textWidth) + 24),
            height: NSView.noIntrinsicMetric
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard isRenamable, !isEditingName else {
            super.mouseDown(with: event)
            return
        }
        beginEditing()
    }

    func beginEditing() {
        guard isRenamable, !isEditingName, let window else { return }
        nameBeforeEditing = stringValue
        isEditable = true
        isSelectable = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        window.makeFirstResponder(self)
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = .white
            editor.selectAll(nil)
        }
        invalidateIntrinsicContentSize()
    }

    /// Ends an edit in progress and renames the folder when the name changed.
    func commitEditing() {
        finishEditing(commit: true)
    }

    /// Ends an edit in progress and restores the previous name.
    func cancelEditing() {
        finishEditing(commit: false)
    }

    private func finishEditing(commit: Bool) {
        guard let previousName = nameBeforeEditing else { return }
        nameBeforeEditing = nil
        if currentEditor() != nil {
            // Ending field editing copies the editor's text into the cell. The nested
            // end-of-editing callback returns early because the edit is already finishing.
            window?.makeFirstResponder(window)
        }
        let editedName = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditable = false
        isSelectable = false
        layer?.backgroundColor = nil

        if commit, !editedName.isEmpty, editedName != previousName {
            stringValue = editedName
            onRename?(editedName)
        } else {
            stringValue = previousName
        }
        invalidateIntrinsicContentSize()
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        invalidateIntrinsicContentSize()
    }

    /// Return, Tab, or a click elsewhere ends field editing.
    func controlTextDidEndEditing(_ notification: Notification) {
        commitEditing()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        // Escape restores the name; a second Escape then leaves the folder as usual.
        cancelEditing()
        return true
    }
}
