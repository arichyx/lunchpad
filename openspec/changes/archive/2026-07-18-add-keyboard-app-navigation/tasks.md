## 1. Navigation Policy

- [x] 1.1 Add an AppKit-independent grid direction and navigation policy that selects the first
  visible item according to the empty-query versus search-entry rules.
- [x] 1.2 Implement bounded row/column movement with 7-by-5 page-local wrapping, occupied-cell
  probing for partially filled pages, and safe behavior for empty, single-item, or invalid state.
- [x] 1.3 Add focused unit tests for every initial direction without search, Down and trailing-Right
  search entry, all four full-page boundary wraps, partial-page empty-cell skipping, and
  empty/single-item pages.

## 2. Active Item State and Presentation

- [x] 2.1 Add a keyboard-active appearance to `AppIconCell` that works for applications and folders,
  composes with pressed feedback, and is reset explicitly during cell reuse/configuration.
- [x] 2.2 Add one optional page-local active index to `IconGridView`, update only the affected visible
  cells during movement, and route movement through the pure navigation policy.
- [x] 2.3 Clear active state before presentation, page changes, search-result reloads, folder entry or
  exit, and catalog reconciliation so no stale index or highlight survives a content change.

## 3. Keyboard Routing

- [x] 3.1 Forward the four AppKit field-editor movement commands from `LunchpadSearchField` to the
  grid, consuming all directions after selection starts, Down Arrow plus a trailing-Right-Arrow
  entry for initial nonempty search, and no left or non-trailing-right command before that entry.
- [x] 3.2 Add one grid activation method that gives an active item priority, otherwise launches the
  first result for a nonempty search, and otherwise does nothing; reuse the existing application and
  folder activation paths.
- [x] 3.3 Route all four plain arrow key codes plus Return and keypad Enter from `LunchpadWindow` to
  the grid, route search-field submission to the same activation method, and remove arrow-key calls
  to previous/next page while preserving Escape behavior.
- [x] 3.4 Verify that an active application launches exactly once, an active folder opens in place,
  an active search result overrides the first result, and a search with no active result retains
  first-result submission.

## 4. Validation

- [x] 4.1 Run `swift test --package-path /Users/arichyx/proj/arichyx/personal/lunchpad` and
  `git diff --check`.
- [x] 4.2 Manually verify empty-query first selection, search caret movement and Down entry,
  subsequent four-direction movement, full and partial page wrapping, no-results behavior, active
  reset after every content transition, Return/keypad Enter activation for apps and folders,
  search submission with and without an active result, and the absence of arrow-key page turns.
