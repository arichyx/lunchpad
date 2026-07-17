## 1. Root Page Persistence Helper

- [x] 1.1 Add a `RootPageStore` type backed by `UserDefaults(suiteName: "com.arichyx.Lunchpad")` with an injectable `UserDefaults` and an injectable `() -> Date` clock, storing the page index as an `Int` and the save time as a `Date` under two dedicated keys.
- [x] 1.2 Define the expiry as a named `TimeInterval` constant of 30 seconds and expose `save(page:)`, which writes the page plus the current clock time.
- [x] 1.3 Implement `restoredPage(availablePageCount:)` returning the saved page clamped to `max(0, availablePageCount - 1)` when both stored values are present and fresh, and `0` when either key is missing, the page index is negative, the save time is older than the expiry, or the save time is later than now. The window passes `rootPageCount` (from `allItems`), never the filtered `pageCount`.
- [x] 1.4 Add focused unit tests covering: restore within expiry, restore after expiry, clamp when the saved page exceeds the current page count, missing page key, missing timestamp key, negative page index, future-dated save time, and a page count of zero.
- [x] 1.5 Add a pure `RootPageSelection.rootPageToSave(folderOpen:searchActive:currentPage:rootPageBeforeEnteringFolder:)` function returning the page to persist, with unit tests for the folder-open, search-active, and default branches (including search-active returning `0` regardless of `currentPage`).

## 2. Wire Persistence Into the Window and Grid

- [x] 2.1 Add a main-actor-owned `RootPageStore` to `LunchpadWindow` (constructed in `AppDelegate` alongside the existing window creation) and pass it through `LunchpadWindow` to the grid restore path.
- [x] 2.2 Add read-only `rootPageForPersistence` and `rootPageCount` accessors on `IconGridView`: `rootPageForPersistence` delegates to the pure `RootPageSelection.rootPageToSave(...)` (returning `rootPageBeforeEnteringFolder` when a folder is open, `0` when a search query is active, and `currentPage` otherwise); `rootPageCount` is computed from `allItems`, not the filtered `pageCount`.
- [x] 2.3 In `LunchpadWindow.close()`, write the current root page via `store.save(page:)` before the hide animation completes, so the most recent root page is durable.
- [x] 2.4 Change `IconGridView.prepareForPresentation()` to accept a restored root page and set `currentPage` from it instead of always zero, preserving the existing folder, search, and page-indicator reset.
- [x] 2.5 In `LunchpadWindow.show()`, call `store.restoredPage(gridView.rootPageCount)` (root count from `allItems`, not the filtered `pageCount`) and pass the result into `prepareForPresentation`, so a just-closed single-page folder or active search does not clamp the restored root page.

## 3. Regression and Verification

- [ ] 3.1 Manually verify the two end-to-end regressions the pure-function tests do not cover: (a) root page 2 -> enter a single-page folder -> close -> reopen within the expiry restores root page 2, not page 1; (b) page through multi-page search results (or launch an app from search) -> close -> reopen returns to root page 1.
- [x] 3.2 Run `swift test --package-path /Users/arichyx/proj/arichyx/personal/lunchpad` and `git diff --check`, and confirm no existing launcher-interface, folder, search, or page-clamp behavior regressed.
- [ ] 3.3 Manually smoke-test in the built app: page to the second page and reopen within a few seconds (restores); reopen after more than 30 seconds (resets to the first page); remove apps to shrink the page count and reopen (clamps); quit and relaunch within the window (restores).
