import AppKit
import QuartzCore

/// A fixed-page collection view: click an item to activate it or empty space to close.
final class LunchpadCollectionView: NSCollectionView {
    var onBackgroundClick: (() -> Void)?
    var onPageDelta: ((Int) -> Void)?
    var onActivateItem: ((IndexPath) -> Void)?

    private var accumulatedHorizontalDelta = 0.0
    private var didTurnPageInCurrentGesture = false
    private var lastDiscreteWheelTurnAt = 0.0
    private var pressedIndexPath: IndexPath?
    private var pressedOnBackground = false

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressedIndexPath = indexPathForItem(at: point)
        pressedOnBackground = pressedIndexPath == nil
        updatePressedAppearance(isInsideOriginalItem: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressedIndexPath != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        updatePressedAppearance(isInsideOriginalItem: indexPathForItem(at: point) == pressedIndexPath)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let releasedIndexPath = indexPathForItem(at: point)
        let originalIndexPath = pressedIndexPath
        let wasBackgroundPress = pressedOnBackground

        updatePressedAppearance(isInsideOriginalItem: false)
        pressedIndexPath = nil
        pressedOnBackground = false

        // Match web click semantics: mouse-down and mouse-up must land on the same item.
        if let originalIndexPath, releasedIndexPath == originalIndexPath {
            onActivateItem?(originalIndexPath)
        } else if wasBackgroundPress, releasedIndexPath == nil {
            onBackgroundClick?()
        }
    }

    private func updatePressedAppearance(isInsideOriginalItem: Bool) {
        guard let pressedIndexPath, let item = item(at: pressedIndexPath) else { return }
        item.view.alphaValue = isInsideOriginalItem ? 0.72 : 1.0
    }

    override func scrollWheel(with event: NSEvent) {
        // Ignore momentum events so one gesture advances at most one page.
        guard event.momentumPhase.isEmpty else { return }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }

        if event.phase == .began {
            accumulatedHorizontalDelta = 0
            didTurnPageInCurrentGesture = false
        }
        accumulatedHorizontalDelta += event.scrollingDeltaX

        let now = ProcessInfo.processInfo.systemUptime
        let isDiscreteWheel = event.phase.isEmpty
        let canTurn = isDiscreteWheel
            ? now - lastDiscreteWheelTurnAt > 0.45
            : !didTurnPageInCurrentGesture

        if canTurn && abs(accumulatedHorizontalDelta) >= 24 {
            // Swiping left shows the next page; swiping right shows the previous page.
            onPageDelta?(accumulatedHorizontalDelta > 0 ? -1 : 1)
            didTurnPageInCurrentGesture = true
            lastDiscreteWheelTurnAt = now
            accumulatedHorizontalDelta = 0
        }

        if event.phase == .ended || event.phase == .cancelled {
            accumulatedHorizontalDelta = 0
        }
    }
}

/// Distributes a fixed 7x5 grid across the available area without scrollable content.
final class LunchpadGridLayout: NSCollectionViewLayout {
    private let columns: Int
    private let rows: Int
    private let itemSize: NSSize
    private var cachedAttributes: [NSCollectionViewLayoutAttributes] = []

    init(columns: Int, rows: Int, itemSize: NSSize) {
        self.columns = columns
        self.rows = rows
        self.itemSize = itemSize
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }

        let count = collectionView.numberOfItems(inSection: 0)
        let bounds = collectionView.bounds
        let horizontalGap = columns > 1
            ? max(0, (bounds.width - CGFloat(columns) * itemSize.width) / CGFloat(columns - 1))
            : 0
        let verticalGap = rows > 1
            ? max(0, (bounds.height - CGFloat(rows) * itemSize.height) / CGFloat(rows - 1))
            : 0

        cachedAttributes = (0..<count).map { item in
            let row = item / columns
            let column = item % columns
            let attributes = NSCollectionViewLayoutAttributes(
                forItemWith: IndexPath(item: item, section: 0)
            )
            attributes.frame = NSRect(
                x: CGFloat(column) * (itemSize.width + horizontalGap),
                y: CGFloat(row) * (itemSize.height + verticalGap),
                width: itemSize.width,
                height: itemSize.height
            )
            return attributes
        }
    }

    override var collectionViewContentSize: NSSize {
        collectionView?.bounds.size ?? .zero
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cachedAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        cachedAttributes.first { $0.indexPath == indexPath }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        true
    }
}

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

/// Top search field, paged 7x5 grid, and bottom page indicator.
final class IconGridView: NSView {
    private enum Layout {
        static let columns = 7
        static let rows = 5
        static let pageCapacity = columns * rows
        static let itemSize = NSSize(width: 120, height: 112)

        // Match Apple's Launchpad with generous outer spacing and room for an expanded Dock.
        static let horizontalPadding: CGFloat = 128
        static let topPadding: CGFloat = 30
        static let desiredBottomPadding: CGFloat = 88
        static let minimumBottomPadding: CGFloat = 40
        static let searchHeight: CGFloat = 28
        static let searchToGridSpacing: CGFloat = 36
        static let gridToPageSpacing: CGFloat = 34
        static let pageIndicatorHeight: CGFloat = 22
    }

    var onLaunch: (() -> Void)?
    var onBackgroundClick: (() -> Void)?

    private let searchField = LunchpadSearchField()
    private let folderTitleLabel = NSTextField(labelWithString: "")
    private let collectionView = LunchpadCollectionView()
    private let pageIndicator = PageIndicatorView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let gridLayout = LunchpadGridLayout(
        columns: Layout.columns,
        rows: Layout.rows,
        itemSize: Layout.itemSize
    )

    private var allItems: [LunchpadItem]
    private var allApps: [AppItem]
    private var filteredItems: [LunchpadItem]
    private var currentFolder: AppFolder?
    private var rootPageBeforeEnteringFolder = 0
    private var currentPage = 0
    private var pressedOnOuterBackground = false
    private var searchTopConstraint: NSLayoutConstraint!
    private var collectionLeadingConstraint: NSLayoutConstraint!
    private var collectionTrailingConstraint: NSLayoutConstraint!
    private var pageBottomConstraint: NSLayoutConstraint!
    private let localizer: AppLocalizer

    init(items: [LunchpadItem], localizer: AppLocalizer) {
        allItems = items
        allApps = items.flatMap(\.apps)
        filteredItems = items
        self.localizer = localizer
        super.init(frame: .zero)
        setup()
        refreshLocalizedContent()
        reloadPage(animated: false)
        AppIconCache.shared.prewarm(allApps)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressedOnOuterBackground = true
    }

    override func mouseDragged(with event: NSEvent) {
        pressedOnOuterBackground = false
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shouldHandleClick = pressedOnOuterBackground && bounds.contains(point)
        pressedOnOuterBackground = false
        if shouldHandleClick {
            handleBackgroundClick()
        }
    }

    var pageCount: Int {
        max(1, Int(ceil(Double(filteredItems.count) / Double(Layout.pageCapacity))))
    }

    /// Page count of the root level, independent of the current folder or search view.
    ///
    /// `pageCount` is derived from `filteredItems`, which still reflects a just-closed folder or search
    /// at `show()` time. Restore must clamp against the root count (from `allItems`) instead, so a
    /// single-page folder cannot shrink the restored multi-page root page.
    var rootPageCount: Int {
        max(1, Int(ceil(Double(allItems.count) / Double(Layout.pageCapacity))))
    }

    /// The root-level page to persist when the launcher is hidden.
    var rootPageForPersistence: Int {
        let searchActive = !searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        return RootPageSelection.rootPageToSave(
            folderOpen: currentFolder != nil,
            searchActive: searchActive,
            currentPage: currentPage,
            rootPageBeforeEnteringFolder: rootPageBeforeEnteringFolder
        )
    }

    private var itemsOnCurrentPage: ArraySlice<LunchpadItem> {
        let start = min(currentPage * Layout.pageCapacity, filteredItems.count)
        let end = min(start + Layout.pageCapacity, filteredItems.count)
        return filteredItems[start..<end]
    }

    func prepareForPresentation(restoredRootPage: Int) {
        currentFolder = nil
        rootPageBeforeEnteringFolder = 0
        searchField.stringValue = ""
        searchField.isHidden = false
        folderTitleLabel.isHidden = true
        filteredItems = allItems
        currentPage = max(0, restoredRootPage)
        reloadPage(animated: false)
    }

    /// Applies a background scan while preserving search, folder, and page context when possible.
    func updateItems(
        _ items: [LunchpadItem],
        animated: Bool,
        invalidatedIconPaths: Set<String>?
    ) {
        if let invalidatedIconPaths {
            AppIconCache.shared.invalidate(paths: invalidatedIconPaths)
        } else {
            AppIconCache.shared.invalidateAll()
        }
        allItems = items
        allApps = items.flatMap(\.apps)

        if let openFolder = currentFolder {
            let refreshedFolder = items.compactMap { item -> AppFolder? in
                guard case .folder(let folder) = item,
                      folder.identifier == openFolder.identifier else {
                    return nil
                }
                return folder
            }.first

            if let refreshedFolder {
                currentFolder = refreshedFolder
                filteredItems = refreshedFolder.apps.map(LunchpadItem.app)
                folderTitleLabel.stringValue = refreshedFolder.name
            } else {
                // Return to the root if the folder disappears; its applications remain on disk.
                currentFolder = nil
                filteredItems = allItems
                currentPage = rootPageBeforeEnteringFolder
                folderTitleLabel.isHidden = true
                searchField.isHidden = false
            }
        } else {
            let query = searchField.stringValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            filteredItems = query.isEmpty
                ? allItems
                : allApps
                    .filter { $0.name.localizedCaseInsensitiveContains(query) }
                    .map(LunchpadItem.app)
        }

        currentPage = min(currentPage, pageCount - 1)
        reloadPage(animated: animated)
        AppIconCache.shared.prewarm(allApps)
    }

    /// Escape exits the current folder first. False tells the window to close Lunchpad.
    @discardableResult
    func dismissOpenFolder() -> Bool {
        guard currentFolder != nil else { return false }
        leaveFolder(animated: true)
        return true
    }

    func showPreviousPage() {
        showPage(currentPage - 1)
    }

    func showNextPage() {
        showPage(currentPage + 1)
    }

    /// Handles window-forwarded scroll events so transparent regions page horizontally and
    /// vertical scrolling never leaks to an underlying application.
    func handleScrollWheel(_ event: NSEvent) {
        collectionView.scrollWheel(with: event)
    }

    func updateScreenInsets(_ insets: NSEdgeInsets, availableHeight: CGFloat) {
        let searchTop = insets.top + Layout.topPadding
        searchTopConstraint.constant = searchTop
        collectionLeadingConstraint.constant = Layout.horizontalPadding + insets.left
        collectionTrailingConstraint.constant = -(Layout.horizontalPadding + insets.right)

        // Reserve 88 points on normal displays; reduce it only when five rows would be clipped.
        let fixedVerticalSpace = searchTop
            + Layout.searchHeight
            + Layout.searchToGridSpacing
            + CGFloat(Layout.rows) * Layout.itemSize.height
            + Layout.gridToPageSpacing
            + Layout.pageIndicatorHeight
            + insets.bottom
        let availableBottomPadding = availableHeight - fixedVerticalSpace
        let bottomPadding = min(
            Layout.desiredBottomPadding,
            max(Layout.minimumBottomPadding, availableBottomPadding)
        )
        pageBottomConstraint.constant = -(insets.bottom + bottomPadding)
        needsLayout = true
    }

    func refreshLocalizedContent() {
        searchField.refreshLocalizedContent(localizer)
        emptyLabel.stringValue = localizer.string("search.empty")
    }

    private func setup() {
        wantsLayer = true

        setupSearchField()
        setupFolderTitleLabel()
        setupCollectionView()
        setupPageIndicator()
        setupEmptyLabel()

        addSubview(searchField)
        addSubview(folderTitleLabel)
        addSubview(collectionView)
        addSubview(pageIndicator)
        addSubview(emptyLabel)

        searchTopConstraint = searchField.topAnchor.constraint(
            equalTo: topAnchor,
            constant: Layout.topPadding
        )
        collectionLeadingConstraint = collectionView.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Layout.horizontalPadding
        )
        collectionTrailingConstraint = collectionView.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -Layout.horizontalPadding
        )
        pageBottomConstraint = pageIndicator.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -Layout.desiredBottomPadding
        )

        NSLayoutConstraint.activate([
            searchTopConstraint,
            searchField.centerXAnchor.constraint(equalTo: centerXAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 260),
            searchField.heightAnchor.constraint(equalToConstant: Layout.searchHeight),

            folderTitleLabel.topAnchor.constraint(equalTo: searchField.topAnchor),
            folderTitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            folderTitleLabel.heightAnchor.constraint(equalTo: searchField.heightAnchor),

            collectionView.topAnchor.constraint(
                equalTo: searchField.bottomAnchor,
                constant: Layout.searchToGridSpacing
            ),
            collectionLeadingConstraint,
            collectionTrailingConstraint,
            collectionView.bottomAnchor.constraint(
                equalTo: pageIndicator.topAnchor,
                constant: -Layout.gridToPageSpacing
            ),

            pageIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            pageBottomConstraint,
            pageIndicator.widthAnchor.constraint(greaterThanOrEqualToConstant: 12),
            pageIndicator.heightAnchor.constraint(equalToConstant: Layout.pageIndicatorHeight),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
        ])
    }

    private func setupSearchField() {
        searchField.onTextChange = { [weak self] query in
            self?.applySearch(query: query)
        }
        searchField.onCancel = { [weak self] in
            self?.onBackgroundClick?()
        }
        searchField.onSubmit = { [weak self] in
            _ = self?.launchFirstSearchResult()
        }
        searchField.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupFolderTitleLabel() {
        folderTitleLabel.font = .systemFont(ofSize: 22, weight: .medium)
        folderTitleLabel.textColor = .white
        folderTitleLabel.alignment = .center
        folderTitleLabel.isHidden = true
        folderTitleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupCollectionView() {
        collectionView.collectionViewLayout = gridLayout
        // NSCollectionView selects on mouse-down; the custom click state machine launches on mouse-up.
        collectionView.isSelectable = false
        collectionView.dataSource = self
        collectionView.backgroundColors = [.clear]
        collectionView.wantsLayer = true
        collectionView.layer?.drawsAsynchronously = true
        collectionView.onBackgroundClick = { [weak self] in
            self?.handleBackgroundClick()
        }
        collectionView.onPageDelta = { [weak self] delta in
            guard let self else { return }
            delta > 0 ? self.showNextPage() : self.showPreviousPage()
        }
        collectionView.onActivateItem = { [weak self] indexPath in
            self?.launchItem(at: indexPath)
        }
        collectionView.register(AppIconCell.self, forItemWithIdentifier: AppIconCell.identifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupPageIndicator() {
        pageIndicator.onSelectPage = { [weak self] page in
            self?.showPage(page)
        }
        pageIndicator.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupEmptyLabel() {
        emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func showPage(_ page: Int) {
        let target = min(max(page, 0), pageCount - 1)
        guard target != currentPage else { return }
        let direction = target > currentPage ? 1 : -1
        currentPage = target
        reloadPage(animated: true, direction: direction)
    }

    private func reloadPage(animated: Bool, direction: Int = 0) {
        currentPage = min(currentPage, pageCount - 1)

        if animated {
            let transition = CATransition()
            transition.duration = direction == 0 ? 0.16 : 0.30
            transition.type = direction == 0 ? .fade : .push
            transition.subtype = direction > 0 ? .fromRight : .fromLeft
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            collectionView.layer?.add(transition, forKey: "page")
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collectionView.reloadData()
        collectionView.layoutSubtreeIfNeeded()
        CATransaction.commit()
        emptyLabel.isHidden = !filteredItems.isEmpty
        pageIndicator.update(pageCount: pageCount, currentPage: currentPage)
    }

    private func applySearch(query rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredItems = query.isEmpty
            ? allItems
            : allApps
                .filter { $0.name.localizedCaseInsensitiveContains(query) }
                .map(LunchpadItem.app)
        currentPage = 0
        reloadPage(animated: true)
    }

    private func launchFirstSearchResult() -> Bool {
        guard !searchField.stringValue.isEmpty else { return false }
        guard case .app(let app)? = filteredItems.first else { return false }
        launch(app)
        return true
    }

    private func launchItem(at indexPath: IndexPath) {
        let pageItems = itemsOnCurrentPage
        guard indexPath.item < pageItems.count else { return }
        let item = pageItems[pageItems.index(pageItems.startIndex, offsetBy: indexPath.item)]

        switch item {
        case .app(let app):
            launch(app)
        case .folder(let folder):
            enterFolder(folder)
        }
    }

    /// Closes Lunchpad immediately and sends the launch request to Launch Services asynchronously.
    private func launch(_ app: AppItem) {
        onLaunch?()

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: app.url,
            configuration: configuration
        ) { _, error in
            if let error {
                print("⚠️ 无法启动 \(app.name)：\(error)")
            }
        }
    }

    /// A folder is a secondary Lunchpad page, not a floating panel, and reuses the root pager.
    private func enterFolder(_ folder: AppFolder) {
        rootPageBeforeEnteringFolder = currentPage
        currentFolder = folder
        filteredItems = folder.apps.map(LunchpadItem.app)
        currentPage = 0

        searchField.stringValue = ""
        searchField.isHidden = true
        folderTitleLabel.stringValue = folder.name
        folderTitleLabel.isHidden = false
        reloadPage(animated: true)
    }

    private func leaveFolder(animated: Bool) {
        guard currentFolder != nil else { return }
        currentFolder = nil
        filteredItems = allItems
        currentPage = min(rootPageBeforeEnteringFolder, pageCount - 1)

        folderTitleLabel.isHidden = true
        searchField.isHidden = false
        reloadPage(animated: animated)
    }

    private func handleBackgroundClick() {
        if currentFolder != nil {
            leaveFolder(animated: true)
        } else {
            onBackgroundClick?()
        }
    }
}

extension IconGridView: NSCollectionViewDataSource {
    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        itemsOnCurrentPage.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(
            withIdentifier: AppIconCell.identifier,
            for: indexPath
        ) as! AppIconCell
        cell.configure(with: itemsOnCurrentPage[itemsOnCurrentPage.index(
            itemsOnCurrentPage.startIndex,
            offsetBy: indexPath.item
        )])
        return cell
    }
}
