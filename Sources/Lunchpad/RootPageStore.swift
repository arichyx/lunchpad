import Foundation

/// Pure selection of which root-level page to persist when the launcher is hidden.
///
/// Extracted from `IconGridView` so the branching is unit-testable without AppKit. The grid feeds its
/// private state into this function; it owns no state of its own.
enum RootPageSelection {
    /// Returns the root-level page to persist.
    ///
    /// - A folder is open: the root page the user was on before entering the folder, so closing inside
    ///   a folder restores that root page rather than the folder's internal page.
    /// - A search query is active: `0`, matching the existing launcher-interface rule that entering a
    ///   query resets to the first page. Persisting the search-results page would jump the user to the
    ///   wrong root page on reopen.
    /// - Otherwise: the current root page.
    static func rootPageToSave(
        folderOpen: Bool,
        searchActive: Bool,
        currentPage: Int,
        rootPageBeforeEnteringFolder: Int
    ) -> Int {
        if folderOpen { return max(0, rootPageBeforeEnteringFolder) }
        if searchActive { return 0 }
        return max(0, currentPage)
    }
}

/// Persists the last-viewed root-level page index and the time it was saved, with a short expiry.
///
/// Backed by the `com.arichyx.Lunchpad` defaults suite (the same plist as the other preferences).
/// Two plain scalar keys are used: the page index as an `Int` and the save time as a `Date`.
/// `UserDefaults` and the clock are injectable so tests can drive expiry without real time.
@MainActor
final class RootPageStore {
    /// Restoring a page saved more than this long ago is treated as "no saved page".
    static let expiry: TimeInterval = 30

    private enum Key {
        static let page = "rootPageIndex"
        static let savedAt = "rootPageSavedAt"
    }

    private let defaults: UserDefaults
    private let clock: () -> Date

    init(defaults: UserDefaults? = nil, clock: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: LunchpadPreferences.domain)
            ?? .standard
        self.clock = clock
    }

    /// Writes the given root page and the current clock time.
    func save(page: Int) {
        defaults.set(max(0, page), forKey: Key.page)
        defaults.set(clock(), forKey: Key.savedAt)
    }

    /// Returns the saved root page clamped to the available page count, or `0` when no fresh, valid
    /// saved page exists (missing timestamp, expired, future-dated, or negative page index).
    ///
    /// The caller passes the **root** page count (`rootPageCount` from `allItems`), never the
    /// filtered `pageCount`, so a just-closed single-page folder cannot shrink the restored root page.
    func restoredPage(availablePageCount: Int) -> Int {
        guard let savedAt = defaults.object(forKey: Key.savedAt) as? Date else {
            return 0
        }
        let now = clock()
        guard savedAt <= now, now.timeIntervalSince(savedAt) <= Self.expiry else {
            return 0
        }
        let savedPage = defaults.integer(forKey: Key.page)
        guard savedPage >= 0 else { return 0 }
        let lastValidPage = max(0, availablePageCount - 1)
        return min(savedPage, lastValidPage)
    }
}
