import AppKit
import QuartzCore

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
        /// Keep enough of a cross-page transfer visible to identify the icon without making it
        /// read as another grid column.
        static let crossPageTransferVisibleFraction: CGFloat = 0.48
    }

    var onLaunch: (() -> Void)?
    var onBackgroundClick: (() -> Void)?
    /// Delivered when a completed drag gesture should be persisted. The delegate commits the
    /// arrangement to the layout store and reloads the presented catalog.
    var onDragCommit: ((LunchpadDragCommit) -> Void)?

    private let searchField = LunchpadSearchField()
    private let folderTitleLabel = NSTextField(labelWithString: "")
    private let collectionView = LunchpadCollectionView()
    private let pageIndicator = PageIndicatorView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let dragFeedbackView = GridDragFeedbackView()
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
    /// Most recently requested collection transition. Core Animation may stop exposing an
    /// explicit animation immediately for an offscreen layer, so retain the request for
    /// diagnostics and deterministic interaction tests.
    private(set) var lastPageTransition: CATransition?
    private var pressedOnOuterBackground = false
    /// Page-local index of the keyboard-active item, or `nil` when nothing is active.
    /// Cleared before every content-changing reload so no stale highlight survives a transition.
    private var activeIndex: Int?
    private var searchTopConstraint: NSLayoutConstraint!
    private var collectionLeadingConstraint: NSLayoutConstraint!
    private var collectionTrailingConstraint: NSLayoutConstraint!
    private var pageBottomConstraint: NSLayoutConstraint!
    private let localizer: AppLocalizer

    // Active drag state. `draggedContainerIndex` is nil whenever no drag is in flight.
    private var draggedContainerIndex: Int?
    /// Floating icon snapshot that follows the cursor; independent of collection-view cells so
    /// page turns and reloads cannot disturb an in-flight drag.
    private var dragSnapshotView: NSView?
    /// Translucent copy parked at the insertion slot during a drag.
    private var dragGhostView: NSView?
    /// Merge target held sticky over its whole cell once its artwork has been hovered.
    private var stickyMergeSlot: Int?
    /// The cell view hidden while its item is being dragged; unhidden when the drag ends.
    private var dragOriginCellView: NSView?
    /// Pointer position relative to the snapshot origin, in this view's coordinates.
    private var dragGrabOffset = NSPoint.zero
    /// Slot-to-cell mapping of the open preview gap; `nil` when icons sit in their own slots.
    private var activePreviewMapping: [Int]?
    private var activePreviewTargetCell: Int?
    /// Invalidates delayed settle callbacks when a reload cancels the active drag or a new drag
    /// starts before an older callback runs.
    private var dragGeneration = 0
    private var lastDragPageTurnAt = CFAbsoluteTime(0)
    /// When the pointer entered the edge strip, or `nil` while it is outside.
    private var dragEdgeEnteredAt: CFAbsoluteTime?
    private var dragEdgeTimer: Timer?
    /// Last reported drag location in collection-view coordinates, for the edge timer.
    private var dragLastPoint = NSPoint.zero
    private let allowsDragArrangement: Bool

    init(
        items: [LunchpadItem],
        localizer: AppLocalizer,
        allowsDragArrangement: Bool = true
    ) {
        allItems = items
        allApps = items.flatMap(\.apps)
        filteredItems = items
        self.localizer = localizer
        self.allowsDragArrangement = allowsDragArrangement
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
        cancelActiveDrag()
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
        cancelActiveDrag()
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
                    .filter { $0.matchesSearchQuery(query) }
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

    /// Handles a directional keyboard command from the window or the search field's field editor.
    ///
    /// Returns `true` when the grid consumed the command (caller should suppress default behavior)
    /// and `false` when the command should fall through to normal text-editing caret movement.
    /// `caretAtEndOfText` is supplied by the search field's field editor; the window path passes
    /// the default of `false` because no caret is present.
    @discardableResult
    func handleNavigationCommand(
        _ direction: GridNavigationDirection,
        caretAtEndOfText: Bool = false
    ) -> Bool {
        let decision = GridNavigationPolicy.entryDecision(
            direction: direction,
            hasActiveItem: activeIndex != nil,
            visibleItemCount: itemsOnCurrentPage.count,
            hasNonEmptySearchQuery: currentSearchQueryIsNonEmpty,
            caretAtEndOfText: caretAtEndOfText
        )

        switch decision {
        case .fallThrough:
            return false
        case .activate(let index):
            setActiveIndex(index)
            return true
        case .move:
            guard let current = activeIndex else { return false }
            let destination = GridNavigationPolicy.move(
                direction: direction,
                activeIndex: current,
                visibleItemCount: itemsOnCurrentPage.count,
                columns: Layout.columns,
                rows: Layout.rows
            )
            setActiveIndex(destination)
            return true
        }
    }

    /// Activates the current keyboard-active item; otherwise launches the first matching
    /// application when a search query is nonempty. Returns `true` when something was activated.
    @discardableResult
    func activateActiveItemOrFirstSearchResult() -> Bool {
        let visibleCount = itemsOnCurrentPage.count
        if let activeIndex, activeIndex < visibleCount {
            clearActiveIndex()
            launchItem(at: IndexPath(item: activeIndex, section: 0))
            return true
        }
        return launchFirstSearchResult()
    }

    /// The trimmed search field contents, used by entry-decision and activation priority rules.
    private var currentSearchQueryIsNonEmpty: Bool {
        !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        addSubview(dragFeedbackView)

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
        searchField.onNavigateDirection = { [weak self] direction, caretAtEnd in
            self?.handleNavigationCommand(direction, caretAtEndOfText: caretAtEnd) ?? false
        }
        searchField.onSubmit = { [weak self] in
            _ = self?.activateActiveItemOrFirstSearchResult()
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
        collectionView.onDragCandidate = { [weak self] indexPath in
            self?.allowsDragCandidate(at: indexPath) ?? false
        }
        collectionView.onDragBegan = { [weak self] indexPath, startPoint in
            self?.handleDragBegan(at: indexPath, startPoint: startPoint)
        }
        collectionView.onDragMoved = { [weak self] point in
            self?.handleDragMoved(to: point)
        }
        collectionView.onDragEnded = { [weak self] point in
            self?.handleDragEnded(at: point)
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
        // The floating drag snapshot is outside the collection view's layer, so the page can
        // keep its normal push transition underneath it. `reloadPage` first normalizes every
        // reused cell, preventing an outgoing preview animation from leaking into the new page.
        reloadPage(animated: true, direction: direction)
    }

    private func reloadPage(animated: Bool, direction: Int = 0) {
        currentPage = min(currentPage, pageCount - 1)
        // A preview moves collection-view item views through the animator. Cancel those layer
        // animations before reloading or reusing the cells; otherwise an outgoing page can write
        // its old frame into a cell that now represents a different item on the new page.
        collectionView.layer?.removeAnimation(forKey: "page")
        resetVisibleItemFrames()
        // Clear before reloading so the previously active cell cannot carry its highlight into a
        // newly visible page, search result list, or folder contents.
        clearActiveIndex()
        lastPageTransition = nil

        if animated {
            let transition = CATransition()
            transition.duration = direction == 0 ? 0.16 : 0.30
            transition.type = direction == 0 ? .fade : .push
            transition.subtype = direction > 0 ? .fromRight : .fromLeft
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            lastPageTransition = transition
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
                .filter { $0.matchesSearchQuery(query) }
                .map(LunchpadItem.app)
        currentPage = 0
        reloadPage(animated: true)
    }

    private func launchFirstSearchResult() -> Bool {
        guard !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
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

    /// Updates the active index and refreshes only the affected visible cells, avoiding icon
    /// reloads or Launch Services traffic during keyboard movement.
    private func setActiveIndex(_ index: Int?) {
        let previous = activeIndex
        guard previous != index else { return }
        activeIndex = index

        if let previous {
            applyActiveState(isActive: false, at: previous)
        }
        if let index {
            applyActiveState(isActive: true, at: index)
        }
    }

    /// Clears the keyboard-active state without touching collection-view contents. Called before
    /// any reload that changes the visible page so the next eligible arrow restarts cleanly.
    private func clearActiveIndex() {
        setActiveIndex(nil)
    }

    private func applyActiveState(isActive: Bool, at index: Int) {
        guard index < itemsOnCurrentPage.count else { return }
        let indexPath = IndexPath(item: index, section: 0)
        guard let cell = collectionView.item(at: indexPath) as? AppIconCell else { return }
        cell.isKeyboardActive = isActive
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
                print("⚠️ Failed to launch \(app.name): \(error)")
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

    // MARK: Drag arrangement

    private var pageStartIndex: Int { currentPage * Layout.pageCapacity }

    /// Search results are a filtered view across the whole catalog; reordering them is undefined.
    private func allowsDragCandidate(at indexPath: IndexPath) -> Bool {
        allowsDragArrangement && !currentSearchQueryIsNonEmpty
    }

    private func handleDragBegan(at indexPath: IndexPath, startPoint: NSPoint) {
        let containerIndex = pageStartIndex + indexPath.item
        guard containerIndex < containerItems.count else { return }

        stopDragEdgeTurning()
        dragGeneration += 1
        lastDragPageTurnAt = 0
        draggedContainerIndex = containerIndex
        clearActiveIndex()

        dragOriginCellView = collectionView.item(at: indexPath)?.view
        dragOriginCellView?.alphaValue = 0

        let slotFrame = convert(gridLayout.frameForSlot(at: indexPath.item), from: collectionView)

        // The ghost is a translucent copy parked at the insertion slot, making the drop target
        // readable; the snapshot follows the cursor and settles onto the ghost's position.
        let ghost = makeDragSnapshot(
            for: containerItems[containerIndex],
            frame: slotFrame,
            iconSide: 80,
            lifted: false
        )
        ghost.alphaValue = 0.45
        ghost.isHidden = true
        addSubview(ghost)
        dragGhostView = ghost

        let snapshot = makeDragSnapshot(for: containerItems[containerIndex], frame: slotFrame)
        addSubview(snapshot)
        dragSnapshotView = snapshot

        let start = convert(startPoint, from: collectionView)
        dragGrabOffset = NSPoint(x: start.x - slotFrame.minX, y: start.y - slotFrame.minY)
    }

    private func handleDragMoved(to point: NSPoint) {
        guard draggedContainerIndex != nil, let dragSnapshotView else { return }
        let local = convert(point, from: collectionView)
        dragSnapshotView.frame.origin = NSPoint(
            x: local.x - dragGrabOffset.x,
            y: local.y - dragGrabOffset.y
        )

        updateDragEdgeTurning(point)

        let candidate = resolveDropCandidate(point: point)
        updateDragPreview(for: candidate)
        updateDragFeedback(for: candidate)
    }

    private func handleDragEnded(at point: NSPoint) {
        let containerIndex = draggedContainerIndex
        guard let containerIndex else {
            finishDrag()
            return
        }
        // A mouse-up ends the edge gesture immediately. The repeating timer must not turn a
        // page while the snapshot is settling or while the commit callback reloads the catalog.
        stopDragEdgeTurning()
        let context = dragContext(draggedContainerIndex: containerIndex)
        let candidate = resolveDropCandidate(point: point)

        guard let commit = DragArrangementPlanner.plan(context: context, candidate: candidate) else {
            // No-op release: the snapshot glides back to its own cell while the gap closes.
            endDragPreview()
            dragGhostView?.isHidden = true
            dragSnapshotView?.isHidden = false
            setDragSnapshotLabelHidden(false)
            let slot = containerIndex - pageStartIndex
            if (0..<itemsOnCurrentPage.count).contains(slot) {
                animateDragSnapshot(toSlot: slot)
            } else {
                fadeOutDragSnapshot()
            }
            let generation = dragGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
                guard let self,
                      self.draggedContainerIndex != nil,
                      self.dragGeneration == generation else { return }
                self.finishDrag()
            }
            return
        }

        // Settle the snapshot into its final cell first, so the commit reload lands on an
        // arrangement that already matches what is on screen.
        if let settleSlot = DragArrangementPlanner.settledPageLocalSlot(
            context: context,
            candidate: candidate
        ), (0..<Layout.pageCapacity).contains(settleSlot) {
            // Once the pointer is released the floating view becomes the final representation;
            // remove the placeholder before settling so two copies never stack in one cell.
            dragGhostView?.isHidden = true
            dragSnapshotView?.isHidden = false
            if case .item = candidate {
                // A merge settles over the target app, whose label remains visible underneath.
                setDragSnapshotLabelHidden(true)
            } else {
                setDragSnapshotLabelHidden(false)
            }
            animateDragSnapshot(toSlot: settleSlot)
            let generation = dragGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
                guard let self,
                      self.draggedContainerIndex != nil,
                      self.dragGeneration == generation else { return }
                // The commit's reload cleans the drag state and replaces the still-hidden
                // origin cell in one pass; unhiding it here would flash the old arrangement.
                self.onDragCommit?(commit)
                if self.draggedContainerIndex != nil, self.dragGeneration == generation {
                    self.finishDrag()
                }
            }
        } else {
            fadeOutDragSnapshot()
            let generation = dragGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                guard let self,
                      self.draggedContainerIndex != nil,
                      self.dragGeneration == generation else { return }
                self.onDragCommit?(commit)
                if self.draggedContainerIndex != nil, self.dragGeneration == generation {
                    self.finishDrag()
                }
            }
        }
    }

    /// Abandons an active drag before the collection view contents are rebuilt. A reload always
    /// follows this call, so shifted frames are left for the reload to replace and the origin
    /// cell stays hidden until the reload reconfigures it.
    func cancelActiveDrag() {
        guard draggedContainerIndex != nil else { return }
        collectionView.cancelDragGesture()
        resetVisibleItemFrames()
        stopDragEdgeTurning()
        finishDrag(restoringOriginCell: false)
    }

    private var containerItems: [LunchpadItem] {
        currentFolder == nil ? allItems : filteredItems
    }

    private func dragContext(draggedContainerIndex index: Int) -> GridDragContext {
        GridDragContext(
            isRootLevel: currentFolder == nil,
            folderIdentifier: currentFolder?.identifier,
            containerItems: containerItems,
            rootItems: currentFolder == nil ? nil : allItems,
            pageStartIndex: pageStartIndex,
            draggedContainerIndex: index,
            newFolderName: localizer.string("folder.new")
        )
    }

    // MARK: Drag snapshot

    /// Builds an icon view shaped like an `AppIconCell`. The lifted snapshot uses a larger icon
    /// with a drop shadow; the ghost placeholder uses cell-sized artwork at reduced opacity.
    private func makeDragSnapshot(
        for item: LunchpadItem,
        frame: NSRect,
        iconSide: CGFloat = 88,
        lifted: Bool = true
    ) -> NSView {
        let container = NSView(frame: frame)
        container.wantsLayer = true
        if lifted {
            container.layer?.cornerRadius = 14
            container.layer?.cornerCurve = .continuous
            container.layer?.shadowColor = NSColor.black.cgColor
            container.layer?.shadowOpacity = 0.45
            container.layer?.shadowRadius = 18
            container.layer?.shadowOffset = CGSize(width: 0, height: -6)
        }

        let iconFrame = NSRect(
            x: (frame.width - iconSide) / 2,
            y: frame.height - iconSide,
            width: iconSide,
            height: iconSide
        )
        switch item {
        case .app(let app):
            let imageView = NSImageView(frame: iconFrame)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.image = AppIconCache.shared.icon(for: app.url)
            container.addSubview(imageView)
        case .folder(let folder):
            let folderView = FolderIconView(frame: iconFrame)
            folderView.configure(with: Array(folder.apps.prefix(9)))
            container.addSubview(folderView)
        }

        // Keep the dragged item's name attached to the lifted view. The stationary ghost is a
        // placement marker and deliberately omits the duplicate label; feedback code hides the
        // lifted label only while it would overlap a ghost or merge target.
        if lifted {
            let label = NSTextField(labelWithString: item.name)
            label.frame = NSRect(x: 0, y: 0, width: frame.width, height: 16)
            label.font = .systemFont(ofSize: 12, weight: .regular)
            label.textColor = .white
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            container.addSubview(label)
        }
        return container
    }

    private func setDragSnapshotLabelHidden(_ hidden: Bool) {
        dragSnapshotView?.subviews
            .compactMap { $0 as? NSTextField }
            .forEach { $0.isHidden = hidden }
    }

    private func animateDragSnapshot(toSlot slot: Int) {
        guard let dragSnapshotView else { return }
        animateItemFrame(
            dragSnapshotView,
            to: convert(gridLayout.frameForSlot(at: slot), from: collectionView)
        )
    }

    private func fadeOutDragSnapshot() {
        guard let dragSnapshotView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            dragSnapshotView.animator().alphaValue = 0
        }
    }

    /// Clears every piece of drag state: snapshot, ghost, hidden origin cell, mapping, and
    /// feedback. When a reload follows (every `cancelActiveDrag` caller), the origin cell stays
    /// hidden and the reload replaces its content — unhiding it first would flash the old
    /// arrangement for one frame or across an animated reload's crossfade.
    private func finishDrag(restoringOriginCell: Bool = true) {
        let draggedIndex = draggedContainerIndex
        if restoringOriginCell {
            if let draggedIndex {
                let slot = draggedIndex - pageStartIndex
                if (0..<itemsOnCurrentPage.count).contains(slot),
                   let currentOriginCell = collectionView.item(
                       at: IndexPath(item: slot, section: 0)
                   )?.view {
                    currentOriginCell.alphaValue = 1
                } else {
                    dragOriginCellView?.alphaValue = 1
                }
            } else {
                dragOriginCellView?.alphaValue = 1
            }
        }
        stopDragEdgeTurning()
        dragSnapshotView?.removeFromSuperview()
        dragSnapshotView = nil
        dragGhostView?.removeFromSuperview()
        dragGhostView = nil
        dragOriginCellView = nil
        draggedContainerIndex = nil
        activePreviewMapping = nil
        activePreviewTargetCell = nil
        stickyMergeSlot = nil
        dragFeedbackView.hide()
    }

    // MARK: Drop resolution

    private func resolveDropCandidate(point: NSPoint) -> GridDropCandidate {
        let draggedSlot: Int? = draggedContainerIndex.flatMap { index in
            let slot = index - pageStartIndex
            if (0..<Layout.pageCapacity).contains(slot) {
                return slot
            }
            // Cross-page drag: encode the approach direction with an out-of-range pseudo slot
            // so the locator's direction-aware insertion snap still applies.
            return index < pageStartIndex ? -1 : Layout.pageCapacity
        }
        let itemCount = itemsOnCurrentPage.count
        let cellOccupants = (0..<Layout.pageCapacity).map {
            occupantSlot(ofCell: $0, itemCount: itemCount)
        }
        let cellFrames = (0..<Layout.pageCapacity).map { gridLayout.frameForSlot(at: $0) }
        let iconFrames = cellFrames.map { iconMergeRect(inCell: $0) }

        // The folder title lives in this view's coordinate space, so its removal zone must be
        // expressed in the collection view's space before it can be tested against the point.
        let removalTargetFrame: NSRect? = currentFolder == nil
            ? nil
            : collectionView.convert(folderTitleLabel.frame, from: folderTitleLabel.superview)

        let raw = GridDropLocator.candidate(
            point: point,
            draggedSlotIndex: draggedSlot,
            cellOccupants: cellOccupants,
            cellFrames: cellFrames,
            iconFrames: iconFrames,
            removalTargetFrame: removalTargetFrame
        )
        let resolved = DragMergeStickiness.resolve(
            raw: raw,
            stickySlot: stickyMergeSlot,
            point: point,
            cellFrames: cellFrames,
            itemCount: itemCount,
            visualCellForSlot: visualCell(forSlot:)
        )
        stickyMergeSlot = resolved.stickySlot
        return resolved.candidate
    }

    /// The merge hit area: the item's full cell minus narrow side margins, covering both the
    /// artwork and its label. The label is part of the item visually, so aligning one icon
    /// over another's name must still merge; the side margins between neighboring items stay
    /// insertion territory.
    private func iconMergeRect(inCell cell: NSRect) -> NSRect {
        cell.insetBy(dx: 12, dy: 0)
    }

    /// The page-local item slot whose icon is visually displayed in `cell`; -1 when empty.
    /// While a preview gap is open, icons occupy shifted cells, so the mapping is inverted.
    private func occupantSlot(ofCell cell: Int, itemCount: Int) -> Int {
        if let activePreviewMapping {
            return activePreviewMapping.firstIndex(of: cell) ?? -1
        }
        return cell < itemCount ? cell : -1
    }

    /// The on-screen cell an item slot is currently displayed in.
    private func visualCell(forSlot slot: Int) -> Int {
        activePreviewMapping?[slot] ?? slot
    }

    // MARK: Page turning

    private enum DragEdge {
        /// Page turning starts only once the pointer leaves the grid for the outer padding. The
        /// last column borders the collection-view edge and must stay freely droppable.
        static let outsideTolerance: CGFloat = 4
        static let dwell: TimeInterval = 0.35
        static let cooldown: TimeInterval = 1.1
    }

    /// Holding the dragged icon inside a narrow edge strip for a dwell interval turns the page,
    /// so an icon can be dragged onto any page. The dwell prevents passing through the strip —
    /// which borders the last column — from turning pages while the user is only aiming a drop.
    ///
    /// A repeating timer drives the decision because holding the mouse still stops
    /// `mouseDragged` events; it must run in `eventTracking` mode to fire during the drag.
    private func updateDragEdgeTurning(_ point: NSPoint) {
        dragLastPoint = point
        if pageCount > 1, edgeDelta(at: point) != nil {
            if dragEdgeEnteredAt == nil {
                dragEdgeEnteredAt = CFAbsoluteTimeGetCurrent()
            }
            startDragEdgeTimer()
        } else {
            stopDragEdgeTurning()
        }
    }

    private func tickDragEdgeTurning() {
        guard draggedContainerIndex != nil else {
            stopDragEdgeTurning()
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        let decision = DragPageEdgePolicy.decide(
            edgeDelta: pageCount > 1 ? edgeDelta(at: dragLastPoint) : nil,
            inEdgeDuration: dragEdgeEnteredAt.map { now - $0 } ?? 0,
            dwell: DragEdge.dwell,
            sinceLastTurn: now - lastDragPageTurnAt,
            cooldown: DragEdge.cooldown,
            targetPage: currentPage + (edgeDelta(at: dragLastPoint) ?? 0),
            pageCount: pageCount
        )
        guard case .turn(let delta) = decision else { return }

        lastDragPageTurnAt = now
        // The dwell restarts before the next turn while the strip stays occupied.
        dragEdgeEnteredAt = now
        // The gap, feedback, and the hidden origin cell all describe the outgoing page.
        // `reloadPage` normalizes the collection cells before it captures the push transition.
        activePreviewMapping = nil
        activePreviewTargetCell = nil
        stickyMergeSlot = nil
        // The ghost belongs to the outgoing page. Keep only the floating snapshot visible until
        // the first drag event on the new page resolves a fresh insertion candidate.
        dragGhostView?.isHidden = true
        dragGhostView?.alphaValue = 0.45
        dragSnapshotView?.isHidden = false
        setDragSnapshotLabelHidden(false)
        dragFeedbackView.hide()
        dragOriginCellView = nil
        showPage(currentPage + delta)
    }

    /// -1 or 1 when the pointer has been pushed beyond the grid into the outer padding,
    /// otherwise `nil`. Reaching this area requires deliberately leaving the icon region.
    private func edgeDelta(at point: NSPoint) -> Int? {
        let bounds = collectionView.bounds
        if point.x < bounds.minX - DragEdge.outsideTolerance { return -1 }
        if point.x > bounds.maxX + DragEdge.outsideTolerance { return 1 }
        return nil
    }

    private func startDragEdgeTimer() {
        guard dragEdgeTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickDragEdgeTurning()
        }
        // The drag runs in eventTracking mode, where default-mode timers never fire.
        RunLoop.main.add(timer, forMode: .default)
        RunLoop.main.add(timer, forMode: .eventTracking)
        dragEdgeTimer = timer
    }

    private func stopDragEdgeTurning() {
        dragEdgeTimer?.invalidate()
        dragEdgeTimer = nil
        dragEdgeEnteredAt = nil
    }

    // MARK: Live gap preview

    /// Opens an animated gap at the insertion target while dragging over empty space, so the
    /// arrangement shown during the drag is exactly the arrangement a release will commit.
    private func updateDragPreview(for candidate: GridDropCandidate) {
        guard case .insertionSlot(let targetCell) = candidate else {
            endDragPreview()
            return
        }
        guard let draggedContainerIndex else { return }

        let draggedSlot = draggedContainerIndex - pageStartIndex
        let itemCount = itemsOnCurrentPage.count

        if (0..<itemCount).contains(draggedSlot) {
            guard itemCount > 1,
                  let mapping = DragPreview.previewSlots(
                    draggedSlot: draggedSlot,
                    targetSlot: targetCell,
                    itemCount: itemCount
                  ) else {
                // Releasing here would change nothing; keep every icon where it is.
                endDragPreview()
                return
            }
            // `previewSlots` clamps a trailing empty-cell drop to the final item position. The
            // ghost must follow that actual landing cell, not the raw empty cell under the
            // pointer, otherwise the preview and the eventual commit disagree.
            applyPreviewMapping(
                mapping,
                targetCell: mapping[draggedSlot],
                excluding: draggedSlot
            )
        } else if draggedContainerIndex > pageStartIndex {
            // Backward cross-page drag: the landing cell onward shifts right; the page's
            // first icon never moves, so the target stays hoverable and mergeable.
            guard itemCount > 0 else {
                endDragPreview()
                return
            }
            guard targetCell < itemCount else {
                // An empty trailing cell already provides an independent landing position; no
                // gap is needed because inserting after this page leaves its icons untouched.
                endDragPreview()
                return
            }
            let mapping = DragPreview.crossPageSlots(
                landingSlot: targetCell,
                itemCount: itemCount,
                forward: false
            )
            applyPreviewMapping(mapping, targetCell: targetCell, excluding: nil)
        } else {
            // Forward cross-page drag: the splice compacts this page toward the previous one,
            // sliding its first item off-page. The gap still belongs to the landing cell, while
            // the displaced first item remains represented by the cross-page splice mapping.
            guard itemCount > 0, targetCell < itemCount else {
                // On a partial final page, an empty trailing cell is already the exact append
                // position and does not require shifting any visible icon.
                endDragPreview()
                return
            }
            let mapping = DragPreview.crossPageSlots(
                landingSlot: targetCell,
                itemCount: itemCount,
                forward: true
            )
            applyPreviewMapping(mapping, targetCell: targetCell, excluding: nil)
        }
    }

    private func applyPreviewMapping(_ mapping: [Int], targetCell: Int, excluding excludedSlot: Int?) {
        guard activePreviewMapping != mapping || activePreviewTargetCell != targetCell else {
            return
        }
        activePreviewMapping = mapping
        activePreviewTargetCell = targetCell
        for slot in 0..<mapping.count where slot != excludedSlot {
            guard let item = collectionView.item(at: IndexPath(item: slot, section: 0)) else {
                continue
            }
            let mappedSlot = mapping[slot]
            animatePreviewItem(
                item,
                to: previewFrame(for: mappedSlot),
                isCrossPageTransfer: mappedSlot < 0 || mappedSlot >= Layout.pageCapacity
            )
        }
    }

    /// Cross-page mappings use -1 and `pageCapacity` as overflow sentinels. Rendering those
    /// through the grid layout would accidentally turn the trailing sentinel into a sixth row;
    /// instead, park the overflow across the screen edge so only part of its icon remains visible.
    private func previewFrame(for mappedSlot: Int) -> NSRect {
        let pageBounds = collectionView.convert(bounds, from: self)
        if mappedSlot < 0 {
            var frame = gridLayout.frameForSlot(at: 0)
            frame.origin.x = pageBounds.minX
                - frame.width * (1 - Layout.crossPageTransferVisibleFraction)
            return frame
        }
        if mappedSlot >= Layout.pageCapacity {
            var frame = gridLayout.frameForSlot(at: Layout.pageCapacity - 1)
            frame.origin.x = pageBounds.maxX
                - frame.width * Layout.crossPageTransferVisibleFraction
            return frame
        }
        return gridLayout.frameForSlot(at: mappedSlot)
    }

    private func endDragPreview() {
        guard activePreviewMapping != nil else { return }
        activePreviewMapping = nil
        activePreviewTargetCell = nil
        restorePageItemFrames()
    }

    /// Returns every page icon except the dragged one to its layout position, closing any gap.
    private func restorePageItemFrames() {
        let draggedSlot = draggedContainerIndex.map { $0 - pageStartIndex }
        for slot in 0..<itemsOnCurrentPage.count {
            guard let item = collectionView.item(at: IndexPath(item: slot, section: 0)) else {
                continue
            }
            if slot == draggedSlot {
                animateItemFrame(item.view, to: gridLayout.frameForSlot(at: slot))
            } else {
                animatePreviewItem(
                    item,
                    to: gridLayout.frameForSlot(at: slot),
                    isCrossPageTransfer: false
                )
            }
        }
    }

    private func animatePreviewItem(
        _ item: NSCollectionViewItem,
        to frame: NSRect,
        isCrossPageTransfer: Bool
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            item.view.animator().frame = frame
            (item as? AppIconCell)?.setCrossPageTransferAppearance(
                isCrossPageTransfer,
                animated: true
            )
        }
    }

    private func animateItemFrame(_ view: NSView, to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().frame = frame
        }
    }

    private func updateDragFeedback(for candidate: GridDropCandidate) {
        switch candidate {
        case .removalTarget:
            dragSnapshotView?.isHidden = false
            setDragSnapshotLabelHidden(false)
            dragGhostView?.isHidden = true
            dragGhostView?.alphaValue = 0.45
            dragFeedbackView.show(
                style: .removalTarget,
                frame: folderTitleLabel.frame.insetBy(dx: -12, dy: -8)
            )
        case .item(let pageLocalSlot):
            dragSnapshotView?.isHidden = false
            // The target cell keeps its own label visible. Preserve the lifted icon and shadow,
            // but suppress its duplicate text while the merge bubble is active.
            setDragSnapshotLabelHidden(true)
            dragGhostView?.isHidden = true
            dragGhostView?.alphaValue = 0.45
            guard (0..<itemsOnCurrentPage.count).contains(pageLocalSlot) else {
                dragFeedbackView.hide()
                return
            }
            // Highlight the cell the target icon is actually displayed in right now.
            let cell = visualCell(forSlot: pageLocalSlot)
            dragFeedbackView.show(
                style: .mergeTarget,
                frame: convert(
                    gridLayout.frameForSlot(at: cell),
                    from: collectionView
                ).insetBy(dx: -6, dy: -6)
            )
        case .insertionSlot(let slotIndex):
            // A same-page preview may clamp a trailing empty-cell target to the final item, and
            // a cross-page preview may make the raw landing cell free. Use the preview's actual
            // gap whenever one is open so the ghost and highlight stay in the same cell.
            let visualSlot = activePreviewTargetCell ?? slotIndex
            let frame = convert(gridLayout.frameForSlot(at: visualSlot), from: collectionView)
            // The ghost may only occupy a cell that is genuinely free: the preview gap (whose
            // occupant is the dragged item itself) or an empty cell. Painting it over a real
            // icon reads as overlapping content instead of a drop target.
            let occupant = occupantSlot(ofCell: visualSlot, itemCount: itemsOnCurrentPage.count)
            let draggedPageLocalSlot = draggedContainerIndex.map { $0 - pageStartIndex }
            let cellIsFree = occupant < 0 || occupant == draggedPageLocalSlot
            dragGhostView?.frame = frame
            dragGhostView?.isHidden = !cellIsFree
            dragSnapshotView?.isHidden = false
            // Preserving the grab offset can make the two representations intersect near the
            // landing cell. Keep both icons continuous, dim the placeholder slightly, and hide
            // only the duplicate floating label until the snapshot moves away again.
            let snapshotOverlapsGhost = cellIsFree
                && dragSnapshotView.map { $0.frame.intersects(frame) } == true
            dragGhostView?.alphaValue = snapshotOverlapsGhost ? 0.28 : 0.45
            setDragSnapshotLabelHidden(snapshotOverlapsGhost)
            dragFeedbackView.show(style: .insertionSlot, frame: frame)
        }
    }

    /// Cancels presentation animations and restores every currently materialized cell to its
    /// nominal layout slot. NSCollectionView may reuse these views during a page/data reload, so
    /// leaving an animator in flight can otherwise place two different items in one cell.
    private func resetVisibleItemFrames() {
        let count = collectionView.numberOfItems(inSection: 0)
        let draggedSlot = draggedContainerIndex.map { $0 - pageStartIndex }
        for slot in 0..<count {
            guard let item = collectionView.item(at: IndexPath(item: slot, section: 0)) else {
                continue
            }
            item.view.layer?.removeAllAnimations()
            item.view.frame = gridLayout.frameForSlot(at: slot)
            if slot != draggedSlot {
                (item as? AppIconCell)?.setCrossPageTransferAppearance(false, animated: false)
            }
        }
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
        // Reapply on every configuration so reused cells cannot inherit a stale highlight.
        cell.isKeyboardActive = (activeIndex == indexPath.item)
        // While a drag is in flight the dragged item is represented by the floating snapshot;
        // keep its cell invisible across page turns so no ghost duplicate appears.
        cell.view.alphaValue = (draggedContainerIndex == pageStartIndex + indexPath.item) ? 0 : 1
        return cell
    }
}
