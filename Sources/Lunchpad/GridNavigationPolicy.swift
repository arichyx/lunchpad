import Foundation

/// A page-local direction used by keyboard navigation within the 7-by-5 grid.
enum GridNavigationDirection {
    case up
    case down
    case left
    case right
}

/// The action the grid should take for a directional command before any movement occurs.
enum GridNavigationEntryDecision: Equatable {
    /// The grid does not own this command; the calling responder may handle it normally.
    case fallThrough
    /// Activate the visible item at the supplied page-local index without applying movement.
    case activate(index: Int)
    /// Apply the direction to the currently active item.
    case move
}

/// Pure, AppKit-free arithmetic for page-local keyboard navigation.
///
/// Movement wraps within the fixed-size grid (seven columns by five rows). On partially filled
/// pages, the probe skips unoccupied cells and retains the active item if no other occupied cell
/// is reachable in the requested row or column. This type is intentionally testable without a
/// window or collection view.
enum GridNavigationPolicy {
    /// Decides how to handle a directional command given the current launcher state.
    ///
    /// Entry rules (matching the launcher-interface spec):
    /// - No visible items: the grid never creates an active item.
    /// - An item is already active: every direction moves it within the grid.
    /// - No active item and an empty query: every direction activates the first visible item.
    /// - No active item and a nonempty query: Down Arrow activates the first visible result.
    ///   Right Arrow activates the second visible result (or the first when only one is visible)
    ///   when the caret is at the end of the query text; otherwise the command falls through to
    ///   the search field's caret movement.
    static func entryDecision(
        direction: GridNavigationDirection,
        hasActiveItem: Bool,
        visibleItemCount: Int,
        hasNonEmptySearchQuery: Bool,
        caretAtEndOfText: Bool
    ) -> GridNavigationEntryDecision {
        guard visibleItemCount > 0 else { return .fallThrough }
        if hasActiveItem { return .move }
        if hasNonEmptySearchQuery {
            switch direction {
            case .down:
                return .activate(index: 0)
            case .right where caretAtEndOfText:
                return .activate(index: min(1, visibleItemCount - 1))
            default:
                return .fallThrough
            }
        }
        return .activate(index: 0)
    }

    /// Moves from `activeIndex` in the requested direction within a fixed-size grid.
    ///
    /// - Parameters:
    ///   - direction: The logical direction to travel.
    ///   - activeIndex: The page-local index of the current item.
    ///   - visibleItemCount: The number of occupied cells on the current page.
    ///   - columns: The fixed number of grid columns (seven for the launcher).
    ///   - rows: The fixed number of grid rows (five for the launcher).
    /// - Returns: The destination index. The current index is returned when the inputs are
    ///   invalid or no other occupied cell is reachable in the requested row or column.
    static func move(
        direction: GridNavigationDirection,
        activeIndex: Int,
        visibleItemCount: Int,
        columns: Int,
        rows: Int
    ) -> Int {
        guard columns > 0, rows > 0, visibleItemCount > 0 else { return activeIndex }
        guard activeIndex >= 0, activeIndex < visibleItemCount else { return activeIndex }

        let currentRow = activeIndex / columns
        let currentCol = activeIndex % columns

        switch direction {
        case .left, .right:
            let step = direction == .right ? 1 : -1
            for probes in 1...columns {
                let candidateCol = ((currentCol + step * probes) % columns + columns) % columns
                let candidateIndex = currentRow * columns + candidateCol
                if candidateIndex != activeIndex, candidateIndex < visibleItemCount {
                    return candidateIndex
                }
            }
            return activeIndex
        case .up, .down:
            let step = direction == .down ? 1 : -1
            for probes in 1...rows {
                let candidateRow = ((currentRow + step * probes) % rows + rows) % rows
                let candidateIndex = candidateRow * columns + currentCol
                if candidateIndex != activeIndex, candidateIndex < visibleItemCount {
                    return candidateIndex
                }
            }
            return activeIndex
        }
    }
}
