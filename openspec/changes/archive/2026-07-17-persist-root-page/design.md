## Context

Lunchpad is a resident accessory app whose full-screen launcher is shown and hidden many times
within a single process lifetime. `IconGridView` owns the in-memory `currentPage`,
`rootPageBeforeEnteringFolder`, and `currentFolder` state. `LunchpadWindow.show()` calls
`IconGridView.prepareForPresentation()` on every presentation, and that method unconditionally resets
`currentPage = 0`, `currentFolder = nil`, and `rootPageBeforeEnteringFolder = 0`. The result is that
the launcher always opens on the first page, even seconds after the user paged to the second page
and closed.

Preferences already persist to `UserDefaults(suiteName: "com.arichyx.Lunchpad")` behind the typed,
injectable `LunchpadPreferences` store, which reads and writes plain scalar values as well as one
packed `Codable` hot-key payload. A page index is just an integer plus a save timestamp, so it needs
only plain scalar keys, not a packed payload. The launcher grid itself is AppKit-heavy and not
unit-tested directly, so behavior that needs verification should live in a small, injectable helper
rather than inside the view.

The fixed 7x5 paged grid, folder-transient behavior (Escape and background clicks leave a folder
before closing, and `prepareForPresentation` always returns to the root), and the
search-resets-to-page-zero rule are all existing invariants this change must preserve.

## Goals / Non-Goals

**Goals:**

- Persist the last-viewed root-level page so reopening within a short window returns the user to it.
- Expire the saved page so genuinely new interactions start on the first page.
- Clamp the restored page to the current valid page count so catalog changes never select a
  non-existent page.
- Keep the save/restore/clamp/expiry logic free of AppKit so it is unit-testable.
- Survive a full process restart, not just show/hide cycles within one running process.

**Non-Goals:**

- Persisting folder pages. Folders remain transient: closing while inside a folder returns to the
  root on the next open, exactly as today.
- Persisting search state or search result pages. Search already resets the page to zero per the
  existing launcher-interface spec.
- Exposing the page index or the expiry as user-facing Settings. It is internal launcher state.
- Changing the fixed 7x5 paged grid model, page-navigation gestures, or the SQLite layout schema.

## Decisions

### 1. Persist the root page index and save timestamp as two plain UserDefaults values

Store the page index as an `Int` and the save time as a `Date` under two dedicated keys in the
existing `com.arichyx.Lunchpad` defaults suite. UserDefaults natively supports both types, so no
`Codable` payload, encoding, or schema versioning is needed. On presentation, read both keys; if
either is missing, the page index is negative, or the save time is older than the expiry (or is in the
future), restore page zero; otherwise restore the saved page (clamped to the current page count).

Two plain scalar keys are preferred over a packed `Codable` payload because the stored data is just
an integer and a timestamp with no nested structure to version or migrate. The existing hot-key
preference uses a versioned payload because its shape changed historically; a page index has no such
history and no realistic need to evolve, so a payload would be over-engineering.

Alternative considered: keep the page only in process memory and skip disk. Rejected because the
user asked for persistence ("持久化") and a resident process can be quit and relaunched; disk is the
single source of truth on every `show()`.

### 2. Save on hide, restore on show, with the window as the boundary

`LunchpadWindow.close()` is the single point where the launcher stops being visible, so it writes the
current root page. `LunchpadWindow.show()` reads the saved value, clamps it against the grid's
`rootPageCount`, and passes the result into `prepareForPresentation`, which sets `currentPage` from it
instead of always zero. `rootPageCount` is computed from `allItems`, not the filtered `pageCount`.
This matters because at `show()` time the grid still reflects the just-closed view: if the user closed
inside a single-page folder, the filtered `pageCount` is 1 and clamping the saved root page against it
would wrongly shrink a multi-page root to the first page. `allItems` is never mutated by folder entry
or search, so `rootPageCount` is correct before `prepareForPresentation` resets the view to the root.

The window queries `IconGridView` for the root page to save: when a folder is open, that is
`rootPageBeforeEnteringFolder`; when a search query is active, it is `0` (search already resets the
page to zero per the launcher-interface spec, so persisting the search-results page would jump the user
to the wrong root page on reopen); otherwise it is `currentPage`. This keeps both folder pages and
search result pages transient while persisting the root page the user was actually on.

Alternative considered: save on every page turn. This adds write traffic and is unnecessary because
the page only needs to be correct on the next open. Saving on hide gives a single, understandable
write point. A crash while the launcher is open leaves the previously-saved (older) state, which
either restores within the expiry window or expires to page zero; both are acceptable.

### 3. Extract the logic into injectable, testable helpers

Introduce a small `RootPageStore` (final class, main-actor like `LunchpadPreferences`) that owns the
two-key reads and writes, expiry comparison, clamping, and fallback. It accepts an injected `UserDefaults`
and an injected `() -> Date` clock so tests can drive expiry without waiting in real time. `IconGridView`
keeps its existing page state; the window calls `store.save(page:)` on close and
`store.restoredPage(rootPageCount:)` on show.

The "which root page to save" branching (folder open vs. search active vs. neither) is pure logic over a
few integers and Booleans, so extract it into a small pure function such as
`RootPageSelection.rootPageToSave(folderOpen:searchActive:currentPage:rootPageBeforeEnteringFolder:)`
and unit-test every branch directly. `IconGridView.rootPageForPersistence` and `rootPageCount` become
thin read-only accessors that feed their private state into that function, keeping the AppKit view out of
the test path. This mirrors how `ApplicationOrderingPolicy` is tested independently of the grid.

This keeps the new logic out of the AppKit view (which has no unit tests) and beside the existing
preferences layer, which is already covered by `PreferencesTests`.

Alternative considered: add the property directly to `LunchpadPreferences`. Rejected because the page
index is transient runtime state with an expiry, not a durable user preference, and co-locating it
with user-configurable settings would muddy that distinction.

### 4. Use a 30-second expiry as a named, tunable constant

Define `RootPageStore.expiry` as a `TimeInterval` constant of 30 seconds. The reasoning: the user's
reported pain is reopening "a few seconds" later and landing on page one. Thirty seconds covers that
reopen-immediately case with margin, while keeping the window short enough that a saved page does not
linger and surprise the user on a later, unrelated open. The classic macOS Launchpad persists
permanently, but the user explicitly requested an expiry and asked for a short one; 30 seconds targets
the reported symptom directly. It is a single constant so it can be tuned later without touching the
logic.

Alternative considered: a longer expiry (for example, five minutes) or no expiry at all. A longer
window keeps stale pages around well after the user stopped looking, which reintroduces the
"why am I on page four?" surprise on an unrelated open; no expiry is permanent persistence, which the
user asked to avoid.

### 5. Clamp on restore and treat bad data as missing

`restoredPage(availablePageCount:)` returns `min(savedPage, max(0, availablePageCount - 1))` when both
keys are present and the save time is fresh, and `0` otherwise. The caller passes the root page count
(`rootPageCount`), not the filtered `pageCount`, so a just-closed single-page folder cannot shrink the
restored root page. A saved page of 0 is a no-op. A missing page key, a missing timestamp key, a
negative page index, and a future-dated timestamp all map to page 0, so a missing or stale value can
never break presentation or select an invalid page. This reuses the same defensive-reading posture
already used by the preferences loaders.

## Risks / Trade-offs

- [Risk] The system clock can move backward, making a freshly saved timestamp appear to be in the
  future. -> Treat a save time later than "now" as expired (not as fresh), so a clock jump never
  resurrects a very old saved page. This is a conservative choice; the user at worst lands on page
  one.
- [Risk] A saved page index can exceed the page count after apps are removed. -> Clamp on restore to
  the current page count, falling back to page 0 when the count is zero.
- [Risk] Saving on hide loses the most recent page if the process is killed while the launcher is
  open. -> Acceptable: the previously saved state either restores within the window or expires. The
  alternative (saving on every page turn) adds write traffic for no behavioral gain.
- [Trade-off] Persisting only the root page means a user who closes inside a folder returns to the
  root on reopen. This is intentional and matches the existing folder-transient invariant.
- [Trade-off] The expiry is fixed, not configurable by the user. It is a named constant so it can be
  revised without schema changes, and exposing it in Settings is an explicit non-goal.
