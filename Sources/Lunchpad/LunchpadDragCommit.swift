import Foundation

/// One ordered slot in a root-level arrangement: an application or a logical folder.
enum LunchpadRootSlot: Equatable {
    case app(identifier: String)
    case folder(identifier: String)
}

/// A completed drag interaction, expressed as the final arrangement of the affected container.
///
/// The drag UI resolves gestures into these values so the layout store can persist each outcome
/// in a single transaction. Root arrangements are always complete: every currently visible root
/// item appears exactly once, in its final order. This lets the first drag under an automatic
/// ordering mode seed the stored positions from the presented arrangement without visibly
/// re-sorting the grid.
enum LunchpadDragCommit: Equatable {
    /// The root level fully rearranged; applications and folders keep their memberships.
    case rootRearranged(slots: [LunchpadRootSlot])

    /// The membership of one folder fully rearranged. `rootSlots` preserve the visible root
    /// order when this is the first drag made under an automatic ordering mode.
    case folderRearranged(
        folderIdentifier: String,
        appIdentifiers: [String],
        rootSlots: [LunchpadRootSlot]
    )

    /// A new logical folder created from applications that were all at the root level. The
    /// folder occupies `insertionIndex` in the root arrangement; `remainingRootSlots` describe
    /// the final root order excluding the new folder.
    case folderCreated(
        name: String,
        appIdentifiers: [String],
        insertionIndex: Int,
        remainingRootSlots: [LunchpadRootSlot]
    )

    /// An application appended to an existing folder. `rootSlots` preserve the visible root
    /// order after the application's former slot is vacated, which is important when this drag
    /// is the first arrangement made from an automatic ordering mode.
    case appAddedToFolder(
        appIdentifier: String,
        folderIdentifier: String,
        rootSlots: [LunchpadRootSlot]
    )

    /// An application moved from a folder back to the root level. `rootSlots` include the moved
    /// application and may still reference the source folder; the store deletes a user folder
    /// left empty and skips its slot.
    case appRemovedToRoot(
        appIdentifier: String,
        sourceFolderIdentifier: String,
        rootSlots: [LunchpadRootSlot]
    )
}
