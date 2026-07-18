## Context

`LunchpadWindow.keyDown(with:)` currently closes on Escape and turns pages directly for the left and
right arrow key codes. `IconGridView` owns the fixed 7-by-5 page and renders it through an
`NSCollectionView`, but deliberately disables AppKit selection because the launcher uses a custom
mouse-down/mouse-up state machine for release-based activation. `LunchpadSearchField` wraps an
editable `NSTextField`; while its field editor is first responder, directional commands are handled
there rather than by the window.

Keyboard item navigation therefore crosses three existing responder layers: the window for arrows
that reach it, the search field for arrows consumed by text editing, and the grid for page-local
state and presentation. The navigation arithmetic itself does not depend on AppKit and should remain
testable without constructing a window or collection view.

The term "item" in this design means every visible grid position. At the root it can be an
application or a logical folder; search results and folder contents contain applications only.

## Goals / Non-Goals

**Goals:**

- Give the current page one optional, visibly active grid item.
- Start at the first visible item on any arrow when the trimmed search query is empty.
- Start a nonempty search result grid on Down Arrow, or on Right Arrow when the caret is at the end
  of the query text (entering at the second visible result, or the first when only one is visible);
  preserve caret movement for the left arrow and for a right arrow before the end of the text until
  a result becomes active.
- Move in the requested row or column and wrap within the 7-by-5 page without changing pages.
- Activate the current item with Return or keypad Enter, launching an application or entering a
  logical folder.
- Preserve Return-to-first-result behavior when a search query is nonempty but no result is active.
- Handle partially filled pages deterministically without selecting an empty cell.
- Keep the navigation and search-entry rules unit-testable outside AppKit.
- Preserve release-based mouse activation and all existing swipe and page-dot navigation.

**Non-Goals:**

- Moving an active item across pages or automatically changing pages at a grid edge.
- Persisting an active item across page changes, searches, folder transitions, catalog changes,
  launcher dismissals, or process launches.
- Changing item ordering, folder membership, grid dimensions, search matching, or page animations.
- Adopting AppKit's built-in collection selection model, which would alter the existing mouse-down
  behavior.

## Decisions

### 1. Keep a page-local active index separate from NSCollectionView selection

`IconGridView` will own an optional index into `itemsOnCurrentPage`. `AppIconCell` will expose an
explicit keyboard-active appearance, and cell configuration will always apply that state so reused
cells cannot retain a stale highlight. Moving the active index updates the previous and next visible
cells without reloading icons or performing filesystem or Launch Services work.

The index will be cleared before a reload that changes the visible page contents: presentation,
manual paging, search changes, folder entry or exit, and catalog reconciliation. The next eligible
arrow command starts at the first item of the newly visible page. This is intentionally simpler and
safer than trying to preserve an index across arrays whose contents and ordering may have changed.

Alternative considered: enable `NSCollectionView.isSelectable` and use
`selectionIndexPaths`. Rejected because AppKit selection occurs on mouse-down, while Lunchpad must
activate only after mouse-up on the same item. A separate keyboard-only state preserves that
invariant and avoids making mouse clicks unexpectedly leave a persistent selection.

### 2. Put directional arithmetic in a pure fixed-grid navigation policy

Add a small AppKit-independent policy that accepts the active page-local index, visible item count,
direction, column count, and row count. If no item is active, the caller's entry rule selects index
zero and does not apply the direction on that same key press.

For an existing active item, convert its index to a row and column. Horizontal movement advances the
column modulo seven while retaining the row; vertical movement advances the row modulo five while
retaining the column. Probe wrapped coordinates in the requested direction until finding an index
below the visible item count. Empty cells on a partially filled page are skipped. If the current item
is the only occupied cell reachable in that row or column, movement returns the current index.

This produces the requested full-page behavior such as Up Arrow from `(row: 0, column: 0)` selecting
`(row: 4, column: 0)`, and it gives partial last pages a deterministic spatial rule without ever
returning an invalid index.

Alternative considered: increment or decrement the linear index and wrap at the first or last item.
Rejected because vertical movement would not preserve the column, and horizontal movement would jump
between rows rather than behaving like a grid.

### 3. Centralize entry gating in IconGridView and route both responder paths to it

Expose one grid method that handles a logical direction and reports whether the command was consumed.
It applies these entry rules before calling the pure movement policy:

- With no active item and an empty trimmed query, every direction selects the first visible item.
- With no active item and a nonempty query, Down Arrow selects the first visible result. Right
  Arrow selects the second visible result (or the first when only one is visible) when the caret is
  at the end of the query text; otherwise Right Arrow, Left Arrow, and Up Arrow fall through to
  caret movement.
- With an active item, every direction moves within the grid regardless of whether a query exists.
- With no visible item, no active index is created.

`LunchpadWindow.keyDown(with:)` will map the four plain arrow key codes to this method and remove the
left/right page-turn branches. `LunchpadSearchField` will map the field-editor command selectors
`moveUp:`, `moveDown:`, `moveLeft:`, and `moveRight:` to a callback owned by `IconGridView`. It
returns `true` only when the grid consumes the command. Consequently, left and right commands with a
nonempty query and no active result fall through to normal `NSTextField` caret movement; Down Arrow
begins result navigation; and subsequent arrows move the active result.

The search field can remain first responder during this handoff. That preserves text entry and
Escape without relying on fragile responder reassignment; its existing submit callback will route
through the grid so Return activates the current result when present and otherwise retains
first-result submission.

Alternative considered: move first responder from the search field to the collection view when Down
Arrow is pressed. Rejected because it would require additional responder plumbing, would obscure
where later typed characters go, and is unnecessary when the field editor can selectively forward
directional commands.

### 4. Use a custom visual state that composes with pressed feedback

Add a subtle rounded translucent highlight or focus treatment to `AppIconCell` that is visually
clear on the launcher backdrop and does not replace the existing pressed alpha feedback. The active
appearance will cover the item consistently for application and folder cells, and configuration
will explicitly turn it on or off for every reused cell.

Alternative considered: reuse the current mouse-pressed alpha reduction as the active state.
Rejected because a persistent dimmed icon reads as disabled or stuck in a press, and mouse drag
cancellation must remain independent of keyboard navigation.

### 5. Keep page navigation on its existing pointer-driven paths

Two-finger horizontal swipes and page-indicator clicks continue to call the existing page methods.
Plain arrow keys no longer call `showPreviousPage()` or `showNextPage()`. A page change clears the
active index before reloading, so keyboard state cannot refer to an item from the prior page and the
first subsequent eligible arrow selects the new page's first item.

Alternative considered: wrap from one page to the next at the first or last grid edge. Rejected
because the requested behavior explicitly forbids arrow-key page changes and calls for overflow
within the current page.

### 6. Route Return and keypad Enter through one active-item activation method

Expose one `IconGridView` method that resolves keyboard activation in priority order:

1. If a page-local item is active, pass its index path to the existing `launchItem(at:)` path. An
   application therefore uses the established immediate-hide-then-asynchronous-launch sequence, and
   a logical folder uses the established folder-entry sequence.
2. If no item is active but the trimmed search query is nonempty, launch the first matching
   application, preserving current search submission behavior.
3. If neither condition applies, report the command as unhandled and launch nothing.

The search field's submit callback and the window's plain Return and keypad Enter key handling will
both call this method. Each responder path consumes the command only once, preventing duplicate
launch requests. Folder entry already reloads the page and will clear keyboard-active state under
the content-transition rule.

Alternative considered: add a second keyboard-specific launch implementation. Rejected because the
existing `launchItem(at:)`, `launch(_:)`, and folder-entry methods already encode the required
immediate dismissal and item-type behavior; duplicating them could make keyboard and mouse
activation diverge.

## Risks / Trade-offs

- [Risk] Field-editor command routing can differ from raw key-code routing. -> Handle the standard
  AppKit movement selectors in `LunchpadSearchField` and keep raw key-code mapping only at the window
  boundary; verify both focused-search and non-search paths manually.
- [Risk] Reused collection cells can display a stale active highlight after reload. -> Apply the
  active flag on every cell configuration and clear page-local state before content-changing
  reloads.
- [Risk] A sparse final row has no occupied cell at the nominal wrapped coordinate. -> Probe the
  fixed row or column through the toroidal grid and skip empty coordinates, with bounded iteration.
- [Risk] Return can be observed by either the field editor or the window depending on first
  responder. -> Route both paths to the same consuming grid method and ensure a single event is
  handled by only one responder.
- [Trade-off] Clearing selection on every visible-content change does not preserve the same
  application through a catalog refresh. This favors predictable, valid state; the next arrow
  restarts at the first currently visible item.
- [Trade-off] Keeping the search field as first responder means its insertion point can remain
  visible while a result is active. This preserves immediate typing and existing search commands,
  while the separate cell highlight communicates which result is active.

## Migration Plan

No data migration or rollout sequencing is required. Implement the pure policy and tests first, then
wire grid state, cell appearance, search command forwarding, directional routing, and shared
Return/Enter activation. Rollback consists of reverting these source changes; there is no stored
state or schema to clean up.

## Open Questions

None.
