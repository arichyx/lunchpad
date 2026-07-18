## Why

Lunchpad currently uses the left and right arrow keys for page changes and offers no keyboard way to
select and launch an application within the visible grid. Users should be able to move a clear
active selection around the current page, press Return or Enter to activate it, and preserve normal
caret movement in a nonempty search field until result navigation begins.

## What Changes

- Add an active-item state and visible highlight for keyboard navigation within the current 7-by-5
  page.
- When no search query is present, make the first arrow-key press activate the first item on the
  current page; subsequent arrow-key presses move the active item in the requested direction.
- Wrap directional movement within the current page, including vertical wrapping from the top row to
  the bottom row, while skipping unoccupied cells on partially filled pages.
- Never change pages as a result of an arrow-key navigation command.
- While a search query is present and the search field owns keyboard focus, reserve the left arrow
  and a mid-text right arrow for caret movement. Activate the first visible search result on Down
  Arrow, and activate the second visible result (or the first when only one is visible) on Right
  Arrow when the caret is at the end of the query text.
- Make Return and keypad Enter activate the selected item: launch an application or enter a logical
  folder. When a search query is nonempty but no result is active, preserve the existing behavior of
  launching the first matching application.
- Clear or re-establish the active item safely when the visible page contents change, including
  paging, search updates, folder transitions, catalog refreshes, and launcher presentation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `launcher-interface`: Replace arrow-key page turning with page-local, wrapping active-item
  navigation, define how navigation begins while search is active, and activate the selected item
  with Return or Enter.

## Impact

- `Sources/Lunchpad/LunchpadWindow.swift`: keyboard-event routing will stop using left and right
  arrows for page changes and will dispatch Return/Enter activation when an item is active.
- `Sources/Lunchpad/IconGridView.swift` and its collection-view cells: active-item state,
  directional movement, lifecycle resets, and visual presentation.
- `Sources/Lunchpad/LunchpadSearchField.swift`: Down Arrow handoff from text editing to the result
  grid while retaining left/right caret behavior, plus selected-result activation on submit.
- `Tests/LunchpadTests/`: focused tests for page-local grid navigation and wrapping.
- No new dependencies, persistence changes, network access, or packaging changes.
