## Why

Every time Lunchpad is shown, `IconGridView.prepareForPresentation()` resets the current page to
zero. Opening the launcher, paging to the second page, closing it, and reopening a few seconds
later lands back on the first page, which feels wrong: the user was just looking at the second page
and their viewing context has not changed. The classic macOS Launchpad remembers the last-viewed
page, but retaining it indefinitely can be equally surprising after the user has clearly moved on.
A short-lived persistence with a sensible expiry preserves short-term context while still returning
to a fresh first page for genuinely new interactions.

## What Changes

- Persist the last-viewed **root-level** page index to the `com.arichyx.Lunchpad` preferences domain
  whenever the launcher is hidden, paired with the wall-clock time at which it was saved.
- On the next presentation, restore the saved root page when it was saved within the expiry window;
  otherwise start at the first page, matching today's behavior.
- Clamp the restored page to the currently valid page count so catalog changes (apps added or
  removed) never select a non-existent page.
- Introduce a 30-second expiry as a single named, tunable constant, chosen so that reopening a few
  seconds later keeps the user on their page while longer gaps return to the first page.
- Treat missing or invalid stored data as "no saved page" and fall back to the first page, so a
  corrupt or unknown value can never break presentation.
- Keep folder pages transient: persistence applies only to the root level. Entering a folder, hiding,
  and reopening still returns to the root page, exactly as today.

## Capabilities

### New Capabilities

<!-- None. This change extends the existing launcher interface rather than introducing a new
     capability. -->

### Modified Capabilities

- `launcher-interface`: Add a requirement that the root-level page is persisted across launcher
  presentations with an expiry, restored when fresh, clamped to the valid page count, and reset to
  the first page when expired, missing, or invalid.

## Impact

- Affects `IconGridView` (page state and `prepareForPresentation`) and `LunchpadWindow` (the show/hide
  boundary where the page is saved and restored).
- Introduces a small, injectable, UserDefaults-backed page-persistence helper with an expiry so the
  save/restore/clamp/expiry logic stays unit-testable without AppKit.
- No SQLite schema, layout data, packaging, localization, or network changes. No new external
  dependencies. The stored value lives alongside existing preferences and is harmless if unread by
  an older build.
