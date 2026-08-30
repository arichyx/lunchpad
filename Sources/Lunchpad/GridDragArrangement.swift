import AppKit

/// Splice math for moving one element within an ordered container.
enum DragSplice {
    /// Returns the element's final index when the element at `from` is inserted before the
    /// element currently at `rawInsertion`, or `nil` when the move changes nothing.
    static func finalIndex(from: Int, rawInsertion: Int, count: Int) -> Int? {
        guard count > 1, from >= 0, from < count else { return nil }
        let insertion = min(max(rawInsertion, 0), count)
        guard insertion != from, insertion != from + 1 else { return nil }
        return insertion < from ? insertion : insertion - 1
    }

    /// Applies the move described by `finalIndex(from:rawInsertion:count:)`.
    static func applyingMove(from: Int, rawInsertion: Int, to items: [LunchpadItem]) -> [LunchpadItem]? {
        guard let final = finalIndex(
            from: from,
            rawInsertion: rawInsertion,
            count: items.count
        ) else { return nil }
        var arranged = items
        let moved = arranged.remove(at: from)
        arranged.insert(moved, at: final)
        return arranged
    }

    /// The raw insertion that lands the dragged element exactly at position `landed`. Removing
    /// the element first shifts later positions down by one, so landing after the origin needs
    /// the raw insertion one further right. This is what keeps the ghost cell, the preview gap,
    /// and the committed position identical.
    static func rawInsertionLanding(at landed: Int, from: Int) -> Int {
        landed > from ? landed + 1 : landed
    }
}

/// Slot mapping for the live drag preview: where each icon sits while a gap is open.
enum DragPreview {
    /// Maps every page slot to the slot it occupies while a gap is previewed for the dragged
    /// icon landing at `targetSlot`. The dragged slot maps to the gap itself. Returns `nil`
    /// when landing there would change nothing, so the caller can keep icons in place.
    static func previewSlots(
        draggedSlot: Int,
        targetSlot: Int,
        itemCount: Int
    ) -> [Int]? {
        guard itemCount > 1, draggedSlot >= 0, draggedSlot < itemCount else { return nil }
        guard let finalSlot = DragSplice.finalIndex(
            from: draggedSlot,
            rawInsertion: DragSplice.rawInsertionLanding(at: targetSlot, from: draggedSlot),
            count: itemCount
        ) else { return nil }

        var order = Array(0..<itemCount)
        order.remove(at: draggedSlot)
        order.insert(draggedSlot, at: finalSlot)
        var slots = Array(0..<itemCount)
        for (position, originalSlot) in order.enumerated() where originalSlot != draggedSlot {
            slots[originalSlot] = position
        }
        slots[draggedSlot] = finalSlot
        return slots
    }

    /// Slot mapping for a cross-page drag hovering this page: the dragged item is not among
    /// the page's items, so there is no vacated slot here. Forward turns (the item comes from
    /// an earlier page) compact the slots up to and including the landing cell leftward — the
    /// first item spills toward the previous page. Backward turns shift the landing cell
    /// onward rightward, with a full page's last mapped slot acting as next-page overflow.
    /// Both mirror the container splice the commit will run, and in both the landing cell ends
    /// up free for the dragged item.
    static func crossPageSlots(
        landingSlot: Int,
        itemCount: Int,
        forward: Bool
    ) -> [Int] {
        guard itemCount > 0 else { return [] }
        let landingSlot = min(max(landingSlot, 0), itemCount - 1)
        return (0..<itemCount).map { slot in
            if forward {
                slot <= landingSlot ? slot - 1 : slot
            } else {
                slot >= landingSlot ? slot + 1 : slot
            }
        }
    }
}

/// Where a drag gesture is hovering, classified in page-local coordinates.
enum GridDropCandidate: Equatable {
    /// Over the icon visually displayed at this page-local item slot. Callers add the page
    /// start when translating to container indices.
    case item(pageLocalSlot: Int)
    /// Over empty space; the value is the nearest page-local cell index.
    case insertionSlot(slotIndex: Int)
    /// Over the open folder's removal target (its title).
    case removalTarget
}

/// Keeps a merge target sticky once its artwork has been hovered. Without this, entering the
/// target's cell from its edge first opens an insertion gap that displaces the target icon, and
/// release-day pointer jitter can drop a hover from the artwork to the cell margin — both
/// silently downgrade a merge into an insertion at the target's position.
enum DragMergeStickiness {
    /// Returns the effective candidate and the sticky slot to carry forward.
    static func resolve(
        raw: GridDropCandidate,
        stickySlot: Int?,
        point: NSPoint,
        cellFrames: [NSRect],
        itemCount: Int,
        visualCellForSlot: (Int) -> Int
    ) -> (candidate: GridDropCandidate, stickySlot: Int?) {
        if case .item(let slot) = raw {
            return (raw, slot)
        }
        guard let sticky = stickySlot, (0..<itemCount).contains(sticky) else {
            return (raw, nil)
        }
        let cell = visualCellForSlot(sticky)
        guard cellFrames.indices.contains(cell), cellFrames[cell].contains(point) else {
            return (raw, nil)
        }
        // The pointer still resides in the hovered icon's cell: the merge decision stands.
        return (.item(pageLocalSlot: sticky), sticky)
    }
}

/// Edge-hover page turning decision. Turning requires the pointer to stay inside the narrow
/// edge strip for a dwell interval first, so dropping an icon in the last column — which
/// borders the strip — is never preempted by a page turn.
enum DragPageEdgePolicy {
    enum Decision: Equatable {
        /// The pointer is outside the strip, or no adjacent page exists in that direction.
        case none
        /// Inside the strip; the dwell or the post-turn cooldown has not elapsed yet.
        case wait
        case turn(delta: Int)
    }

    static func decide(
        edgeDelta: Int?,
        inEdgeDuration: TimeInterval,
        dwell: TimeInterval,
        sinceLastTurn: TimeInterval,
        cooldown: TimeInterval,
        targetPage: Int,
        pageCount: Int
    ) -> Decision {
        guard let edgeDelta else { return .none }
        guard inEdgeDuration >= dwell, sinceLastTurn >= cooldown else { return .wait }
        guard (0..<max(pageCount, 1)).contains(targetPage) else { return .none }
        return .turn(delta: edgeDelta)
    }
}

enum GridDropLocator {
    /// Classifies a drag location in page-local coordinates.
    ///
    /// `cellOccupants` maps each on-screen grid cell to the page-local item slot whose icon is
    /// currently displayed there, or -1 when the cell is empty. While a preview gap is open this
    /// differs from the identity mapping, so hovering a shifted icon targets the icon actually
    /// under the pointer instead of whichever item used to own that cell.
    ///
    /// `iconFrames` are the merge hit areas — the icon artwork region inside each cell, not the
    /// full cell rect. Hovering the artwork merges; hovering anywhere else in the cell inserts.
    static func candidate(
        point: NSPoint,
        draggedSlotIndex: Int?,
        cellOccupants: [Int],
        cellFrames: [NSRect],
        iconFrames: [NSRect],
        removalTargetFrame: NSRect?
    ) -> GridDropCandidate {
        if let removalTargetFrame,
           removalTargetFrame.insetBy(dx: -12, dy: -8).contains(point) {
            return .removalTarget
        }

        for (cell, occupant) in cellOccupants.enumerated()
        where cell < iconFrames.count {
            guard occupant >= 0, occupant != draggedSlotIndex,
                  iconFrames[cell].contains(point) else { continue }
            return .item(pageLocalSlot: occupant)
        }

        var nearestCell = 0
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for (cell, frame) in cellFrames.enumerated() {
            let center = NSPoint(x: frame.midX, y: frame.midY)
            let distance = hypot(point.x - center.x, point.y - center.y)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestCell = cell
            }
        }

        // Hovering an occupied cell must not open the gap in place of that icon: it would slide
        // toward the pointer's approach side and become impossible to hover (and merge with).
        // Snap to the boundary on the far side of the approach direction so the icon stays put.
        // This also covers the open space between cells, where the approach spends most of its
        // time before crossing the target cell's edge.
        let nearestOccupant = nearestCell < cellOccupants.count ? cellOccupants[nearestCell] : -1
        if nearestOccupant >= 0, nearestOccupant != draggedSlotIndex {
            let draggingBackward = draggedSlotIndex.map { $0 > nearestCell } ?? false
            if draggingBackward {
                if point.x >= cellFrames[nearestCell].midX,
                   nearestCell + 1 < cellFrames.count {
                    nearestCell += 1
                }
            } else if point.x < cellFrames[nearestCell].midX, nearestCell > 0 {
                nearestCell -= 1
            }
        }
        return .insertionSlot(slotIndex: nearestCell)
    }
}

/// Everything the drag UI knows about the container a drag started in.
struct GridDragContext {
    let isRootLevel: Bool
    /// Identifier of the open folder when `isRootLevel` is false.
    let folderIdentifier: String?
    /// Full item order of the container: all root items, or the open folder's applications.
    let containerItems: [LunchpadItem]
    /// The full root arrangement, required for removals from a folder; `nil` at the root level.
    let rootItems: [LunchpadItem]?
    /// Container index of the container's first visible page slot.
    let pageStartIndex: Int
    /// Container index of the dragged item.
    let draggedContainerIndex: Int
    /// Localized name for a folder created by dropping one application onto another.
    let newFolderName: String
}

enum DragArrangementPlanner {
    /// Resolves a drag into the persisted arrangement it produces, or `nil` when the drop is a
    /// no-op (released over its own slot, without a target, or with a stale container).
    static func plan(
        context: GridDragContext,
        candidate: GridDropCandidate
    ) -> LunchpadDragCommit? {
        let draggedIndex = context.draggedContainerIndex
        guard draggedIndex >= 0, draggedIndex < context.containerItems.count else { return nil }

        if context.isRootLevel {
            switch candidate {
            case .removalTarget:
                return nil
            case .item(let pageLocalSlot):
                return planRootDropOnItem(
                    context: context,
                    targetIndex: context.pageStartIndex + pageLocalSlot
                )
            case .insertionSlot(let slotIndex):
                return planRootReorder(
                    context: context,
                    landedContainerIndex: context.pageStartIndex + slotIndex
                )
            }
        }

        switch candidate {
        case .removalTarget:
            guard case .app(let draggedApp) = context.containerItems[draggedIndex] else {
                return nil
            }
            return planRemovalToRoot(context: context, draggedApp: draggedApp)
        case .item(let pageLocalSlot):
            return planFolderReorder(
                context: context,
                landedContainerIndex: context.pageStartIndex + pageLocalSlot
            )
        case .insertionSlot(let slotIndex):
            return planFolderReorder(
                context: context,
                landedContainerIndex: context.pageStartIndex + slotIndex
            )
        }
    }

    /// The page-local slot the dragged icon will occupy once `plan`'s commit for this candidate
    /// reloads, or `nil` when the release does not settle on the visible page (folder removal
    /// or a cross-page drop). The drag snapshot glides to this slot before the reload lands.
    /// Only call with a candidate for which `plan` returned a commit.
    static func settledPageLocalSlot(
        context: GridDragContext,
        candidate: GridDropCandidate
    ) -> Int? {
        let dragged = context.draggedContainerIndex
        let pageStart = context.pageStartIndex
        func localSlot(_ containerIndex: Int) -> Int? {
            let slot = containerIndex - pageStart
            return slot >= 0 ? slot : nil
        }
        guard dragged >= 0, dragged < context.containerItems.count else { return nil }

        if context.isRootLevel {
            switch candidate {
            case .removalTarget:
                return nil
            case .item(let pageLocalSlot):
                let targetIndex = pageStart + pageLocalSlot
                switch (context.containerItems[dragged], context.containerItems[targetIndex]) {
                case (.app, .app):
                    return localSlot(folderCreationInsertionIndex(
                        draggedIndex: dragged,
                        targetIndex: targetIndex
                    ))
                case (.app, .folder):
                    // The application joins the folder; the folder keeps its slot.
                    return localSlot(targetIndex)
                case (.folder, _):
                    return DragSplice.finalIndex(
                        from: dragged,
                        rawInsertion: DragSplice.rawInsertionLanding(
                            at: targetIndex,
                            from: dragged
                        ),
                        count: context.containerItems.count
                    ).flatMap(localSlot)
                }
            case .insertionSlot(let slotIndex):
                return DragSplice.finalIndex(
                    from: dragged,
                    rawInsertion: DragSplice.rawInsertionLanding(
                        at: pageStart + slotIndex,
                        from: dragged
                    ),
                    count: context.containerItems.count
                ).flatMap(localSlot)
            }
        }

        switch candidate {
        case .removalTarget:
            return nil
        case .item(let pageLocalSlot):
            return DragSplice.finalIndex(
                from: dragged,
                rawInsertion: DragSplice.rawInsertionLanding(
                    at: pageStart + pageLocalSlot,
                    from: dragged
                ),
                count: context.containerItems.count
            ).flatMap(localSlot)
        case .insertionSlot(let slotIndex):
            return DragSplice.finalIndex(
                from: dragged,
                rawInsertion: DragSplice.rawInsertionLanding(
                    at: pageStart + slotIndex,
                    from: dragged
                ),
                count: context.containerItems.count
            ).flatMap(localSlot)
        }
    }

    private static func planRootDropOnItem(
        context: GridDragContext,
        targetIndex: Int
    ) -> LunchpadDragCommit? {
        guard targetIndex != context.draggedContainerIndex,
              targetIndex >= 0,
              targetIndex < context.containerItems.count else { return nil }

        let dragged = context.containerItems[context.draggedContainerIndex]
        let target = context.containerItems[targetIndex]

        switch (dragged, target) {
        case (.app(let draggedApp), .app(let targetApp)):
            return planFolderCreation(
                context: context,
                draggedApp: draggedApp,
                targetApp: targetApp,
                targetIndex: targetIndex
            )
        case (.app(let draggedApp), .folder(let targetFolder)):
            return .appAddedToFolder(
                appIdentifier: draggedApp.identifier,
                folderIdentifier: targetFolder.identifier,
                rootSlots: context.containerItems.enumerated().compactMap { index, item in
                    index == context.draggedContainerIndex ? nil : item.rootSlot
                }
            )
        case (.folder, _):
            // Folders reorder; they never merge into applications or other folders.
            return planRootReorder(context: context, landedContainerIndex: targetIndex)
        }
    }

    private static func planRootReorder(
        context: GridDragContext,
        landedContainerIndex: Int
    ) -> LunchpadDragCommit? {
        guard let arranged = DragSplice.applyingMove(
            from: context.draggedContainerIndex,
            rawInsertion: DragSplice.rawInsertionLanding(
                at: landedContainerIndex,
                from: context.draggedContainerIndex
            ),
            to: context.containerItems
        ) else { return nil }
        return .rootRearranged(slots: arranged.map(\.rootSlot))
    }

    private static func planFolderCreation(
        context: GridDragContext,
        draggedApp: AppItem,
        targetApp: AppItem,
        targetIndex: Int
    ) -> LunchpadDragCommit? {
        // The folder takes the target's slot; both applications leave the root.
        let draggedIndex = context.draggedContainerIndex
        var remaining = context.containerItems
        remaining.remove(at: max(draggedIndex, targetIndex))
        remaining.remove(at: min(draggedIndex, targetIndex))
        let insertionIndex = folderCreationInsertionIndex(
            draggedIndex: draggedIndex,
            targetIndex: targetIndex
        )

        return .folderCreated(
            name: context.newFolderName,
            appIdentifiers: [targetApp.identifier, draggedApp.identifier],
            insertionIndex: insertionIndex,
            remainingRootSlots: remaining.map(\.rootSlot)
        )
    }

    /// A folder created by dropping on an app occupies the target app's former container index,
    /// adjusted when the dragged app sat before the target and leaves a hole behind it.
    private static func folderCreationInsertionIndex(draggedIndex: Int, targetIndex: Int) -> Int {
        draggedIndex < targetIndex ? targetIndex - 1 : targetIndex
    }

    private static func planFolderReorder(
        context: GridDragContext,
        landedContainerIndex: Int
    ) -> LunchpadDragCommit? {
        guard let folderIdentifier = context.folderIdentifier,
              let rootItems = context.rootItems else { return nil }
        guard let arranged = DragSplice.applyingMove(
            from: context.draggedContainerIndex,
            rawInsertion: DragSplice.rawInsertionLanding(
                at: landedContainerIndex,
                from: context.draggedContainerIndex
            ),
            to: context.containerItems
        ) else { return nil }

        let appIdentifiers = arranged.compactMap { item -> String? in
            guard case .app(let app) = item else { return nil }
            return app.identifier
        }
        return .folderRearranged(
            folderIdentifier: folderIdentifier,
            appIdentifiers: appIdentifiers,
            rootSlots: rootItems.map(\.rootSlot)
        )
    }

    private static func planRemovalToRoot(
        context: GridDragContext,
        draggedApp: AppItem
    ) -> LunchpadDragCommit? {
        guard let folderIdentifier = context.folderIdentifier, let rootItems = context.rootItems
        else { return nil }
        guard let folderIndex = rootItems.firstIndex(where: { item in
            guard case .folder(let folder) = item else { return false }
            return folder.identifier == folderIdentifier
        }) else { return nil }

        // The application lands right after the folder it left.
        var slots = rootItems.map(\.rootSlot)
        slots.insert(.app(identifier: draggedApp.identifier), at: folderIndex + 1)
        return .appRemovedToRoot(
            appIdentifier: draggedApp.identifier,
            sourceFolderIdentifier: folderIdentifier,
            rootSlots: slots
        )
    }
}

extension LunchpadItem {
    /// The drag-arrangement slot describing this item's identity.
    var rootSlot: LunchpadRootSlot {
        switch self {
        case .app(let app): .app(identifier: app.identifier)
        case .folder(let folder): .folder(identifier: folder.identifier)
        }
    }
}
