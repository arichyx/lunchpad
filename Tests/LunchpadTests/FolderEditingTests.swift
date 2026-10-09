import AppKit
import XCTest
@testable import Lunchpad

@MainActor
final class FolderEditingTests: XCTestCase {
    private var window: NSWindow!

    override func tearDown() async throws {
        window = nil
        try await super.tearDown()
    }

    private func makeTitleField(name: String) -> FolderTitleField {
        let field = FolderTitleField()
        field.stringValue = name
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 28)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: -5000, width: 400, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(field)
        return field
    }

    private func type(_ text: String, into field: FolderTitleField) throws {
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.string = text
    }

    func testCommitReportsTrimmedChangedName() throws {
        let field = makeTitleField(name: "New Folder")
        field.isRenamable = true
        var renames: [String] = []
        field.onRename = { renames.append($0) }

        field.beginEditing()
        XCTAssertTrue(field.isEditingName)
        try type("  Games ", into: field)
        field.commitEditing()

        XCTAssertFalse(field.isEditingName)
        XCTAssertEqual(renames, ["Games"])
        XCTAssertEqual(field.stringValue, "Games")
        XCTAssertFalse(field.isEditable)
    }

    func testEscapeRestoresThePreviousName() throws {
        let field = makeTitleField(name: "New Folder")
        field.isRenamable = true
        field.onRename = { _ in XCTFail("Escape must not rename") }

        field.beginEditing()
        try type("Games", into: field)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertTrue(
            field.control(
                field,
                textView: editor,
                doCommandBy: #selector(NSResponder.cancelOperation(_:))
            )
        )

        XCTAssertFalse(field.isEditingName)
        XCTAssertEqual(field.stringValue, "New Folder")
    }

    func testEmptyOrUnchangedNameIsNotReported() throws {
        let field = makeTitleField(name: "Games")
        field.isRenamable = true
        field.onRename = { _ in XCTFail("Nothing changed") }

        field.beginEditing()
        try type("   ", into: field)
        field.commitEditing()
        XCTAssertEqual(field.stringValue, "Games")

        field.beginEditing()
        try type("Games", into: field)
        field.commitEditing()
    }

    func testEditingTitleKeepsATypingAreaAndFitsItsText() throws {
        let field = makeTitleField(name: "New Folder")
        let readOnlyWidth = field.intrinsicContentSize.width
        XCTAssertGreaterThan(readOnlyWidth, 60)
        field.isRenamable = true

        field.beginEditing()
        XCTAssertGreaterThanOrEqual(field.intrinsicContentSize.width, 160)
        try type(String(repeating: "Long Name ", count: 6), into: field)
        XCTAssertGreaterThan(field.intrinsicContentSize.width, readOnlyWidth * 2)
        field.cancelEditing()

        XCTAssertEqual(field.intrinsicContentSize.width, readOnlyWidth)
    }

    func testReadOnlyTitleDoesNotEnterEditing() {
        let field = makeTitleField(name: "Other")
        field.isRenamable = false

        field.beginEditing()

        XCTAssertFalse(field.isEditingName)
        XCTAssertNil(field.currentEditor())
    }

    // MARK: Context menu

    private func app(_ name: String) -> AppItem {
        AppItem(
            identifier: "app.\(name.lowercased())",
            bundleIdentifier: "app.\(name.lowercased())",
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            creationDate: nil,
            modificationDate: nil
        )
    }

    private func makeGrid(allowsEditing: Bool = true) -> IconGridView {
        let items: [LunchpadItem] = [
            .app(app("Alpha")),
            .folder(AppFolder(
                identifier: "folder.games",
                name: "Games",
                apps: [app("Bravo"), app("Charlie")],
                isSystem: false
            )),
            .folder(AppFolder(
                identifier: LunchpadLayoutStore.otherFolderIdentifier,
                name: "Other",
                apps: [app("Delta")],
                isSystem: true
            )),
        ]
        let grid = IconGridView(
            items: items,
            localizer: AppLocalizer(language: .english),
            allowsDragArrangement: allowsEditing
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: -5000, width: 1600, height: 1000),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = grid
        grid.updateScreenInsets(
            NSEdgeInsets(top: 40, left: 0, bottom: 40, right: 0),
            availableHeight: 1000
        )
        grid.layoutSubtreeIfNeeded()
        return grid
    }

    func testUserFolderMenuDeletesThatFolder() throws {
        let grid = makeGrid()
        var deleted: [String] = []
        grid.onFolderDelete = { deleted.append($0) }

        let menu = try XCTUnwrap(grid.folderContextMenu(forItemAt: IndexPath(item: 1, section: 0)))
        XCTAssertEqual(menu.items.map(\.title), ["Rename Folder", "Delete Folder"])
        menu.performActionForItem(at: 1)

        XCTAssertEqual(deleted, ["folder.games"])
    }

    func testRenameMenuOpensTheFolderWithAnEditableTitle() throws {
        let grid = makeGrid()

        let menu = try XCTUnwrap(grid.folderContextMenu(forItemAt: IndexPath(item: 1, section: 0)))
        menu.performActionForItem(at: 0)

        XCTAssertTrue(grid.isEditingFolderTitle)
        XCTAssertTrue(grid.dismissOpenFolder())
        XCTAssertFalse(grid.isEditingFolderTitle)
    }

    func testAppsSystemFoldersAndFallbackLayoutOfferNoMenu() {
        XCTAssertNil(makeGrid().folderContextMenu(forItemAt: IndexPath(item: 0, section: 0)))
        XCTAssertNil(makeGrid().folderContextMenu(forItemAt: IndexPath(item: 2, section: 0)))
        XCTAssertNil(
            makeGrid(allowsEditing: false)
                .folderContextMenu(forItemAt: IndexPath(item: 1, section: 0))
        )
    }
}
