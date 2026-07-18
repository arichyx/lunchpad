## ADDED Requirements

### Requirement: Page-local keyboard item navigation

Lunchpad SHALL maintain at most one visibly active item in the current 7-by-5 grid page and SHALL
move that active item with plain directional arrow keys without selecting an unoccupied grid cell.
At the root level, visible items include applications and logical folders; search results and folder
contents contain applications.

#### Scenario: First arrow begins navigation without a search query

- **WHEN** the current page contains visible items, the trimmed search query is empty, no item is
  active, and the user presses any directional arrow key
- **THEN** Lunchpad visibly activates the first item on the current page without applying that
  direction as an additional movement

#### Scenario: Directional movement advances from an active item

- **WHEN** an item is active and the user presses a directional arrow key
- **THEN** Lunchpad activates the nearest occupied cell in that direction within the same row or
  column and deactivates the previous item

#### Scenario: Vertical movement wraps within a full page

- **WHEN** the item at row zero and column zero is active on a full 7-by-5 page and the user presses
  Up Arrow
- **THEN** Lunchpad activates the item at row four and column zero on the same page

#### Scenario: Horizontal movement wraps within a row

- **WHEN** an item in the first column is active and the user presses Left Arrow
- **THEN** Lunchpad wraps to the last occupied cell in the same row without changing pages

#### Scenario: Movement skips empty cells on a partial page

- **WHEN** wrapped movement encounters one or more unoccupied cells on a partially filled page
- **THEN** Lunchpad continues in the requested direction within the same row or column until it
  reaches an occupied cell, or retains the current item if no other occupied cell is reachable

#### Scenario: Empty page cannot create an active item

- **WHEN** the current page has no visible items and the user presses a directional arrow key
- **THEN** Lunchpad keeps the page unchanged and does not display an active item

#### Scenario: Down Arrow enters nonempty search results

- **WHEN** a trimmed search query is nonempty, matching applications are visible, no result is
  active, and the search field receives Down Arrow
- **THEN** Lunchpad activates the first visible search result without applying an additional
  downward movement

#### Scenario: Left arrow and non-trailing right arrow retain search caret control before navigation begins

- **WHEN** a trimmed search query is nonempty, no result is active, and the search field receives
  Left Arrow, or receives Right Arrow while the caret is not at the end of the query text
- **THEN** no result becomes active and the search field performs its normal caret movement

#### Scenario: Right arrow at the end of the query enters search results at the second item

- **WHEN** a trimmed search query is nonempty, no result is active, the caret is at the end of the
  query text, and the search field receives Right Arrow
- **THEN** Lunchpad activates the second visible search result, or the first visible result when
  only one result is visible

#### Scenario: Up Arrow does not enter nonempty search results

- **WHEN** a trimmed search query is nonempty, no result is active, and the search field receives Up
  Arrow
- **THEN** no result becomes active and keyboard focus remains in the search field

#### Scenario: All directions navigate after a search result becomes active

- **WHEN** a search result is active and the search field receives any directional arrow key
- **THEN** Lunchpad moves the active result according to the same page-local wrapping rules used
  without a search query

#### Scenario: Visible contents change

- **WHEN** presentation, paging, search input, folder navigation, or catalog reconciliation changes
  the visible contents of the grid
- **THEN** Lunchpad clears any prior active item so the next eligible arrow command starts from the
  first item of the current contents

### Requirement: Keyboard activation of the active item

Lunchpad SHALL activate the current keyboard-active item when the user presses Return or keypad
Enter, using the same application-launch and folder-entry behavior as release-based mouse
activation.

#### Scenario: User activates an application from the keyboard

- **WHEN** an application is active and the user presses Return or keypad Enter
- **THEN** Lunchpad hides immediately and requests that macOS launch that application exactly once

#### Scenario: User activates a logical folder from the keyboard

- **WHEN** a logical folder is active at the root level and the user presses Return or keypad Enter
- **THEN** Lunchpad enters that folder, keeps the launcher visible, and clears the prior root active
  item

#### Scenario: User presses Return without an active item or search

- **WHEN** no item is active, the trimmed search query is empty, and the user presses Return or
  keypad Enter
- **THEN** Lunchpad does not launch an application or enter a folder

## MODIFIED Requirements

### Requirement: Controlled page navigation

Lunchpad SHALL support two-finger horizontal swipes and page-indicator clicks without allowing one
continuous gesture to skip multiple pages. Plain directional arrow keys SHALL remain within the
current page and MUST NOT change the current page.

#### Scenario: User swipes left or right

- **WHEN** horizontal scroll distance crosses the paging threshold
- **THEN** a leftward swipe advances one page and a rightward swipe returns one page

#### Scenario: Trackpad momentum continues

- **WHEN** momentum events follow a completed page turn
- **THEN** Lunchpad ignores them for paging so the gesture advances at most one page

#### Scenario: User scrolls vertically over Lunchpad

- **WHEN** a vertical scroll event reaches the launcher window
- **THEN** Lunchpad consumes it without paging and without forwarding it to an underlying
  application

#### Scenario: User clicks a page dot

- **WHEN** the user presses and releases within a page indicator's hit target
- **THEN** Lunchpad changes to that page without treating the click as a background dismissal

#### Scenario: User presses an arrow key at a page boundary

- **WHEN** an active item is at a row or column boundary and the user presses the arrow key pointing
  beyond that boundary
- **THEN** Lunchpad wraps item selection within the current page and leaves the current page index
  unchanged

### Requirement: Application search

Lunchpad SHALL filter all discovered applications by localized display name using a trimmed,
case-insensitive substring query. Return or keypad Enter SHALL activate the keyboard-active result
when one exists and otherwise SHALL launch the first matching application.

#### Scenario: User enters a query

- **WHEN** search text changes at the root level
- **THEN** Lunchpad resets to page zero and displays matching applications without folder wrappers

#### Scenario: Search has no results

- **WHEN** no application name contains the query
- **THEN** Lunchpad displays an empty-result message

#### Scenario: User submits a search before result navigation

- **WHEN** the search field is nonempty, no result is active, and the user presses Return or keypad
  Enter
- **THEN** Lunchpad launches the first matching application

#### Scenario: User submits an active search result

- **WHEN** the search field is nonempty, a result is active, and the user presses Return or keypad
  Enter
- **THEN** Lunchpad launches the active matching application instead of the first result

#### Scenario: User presses Escape while searching

- **WHEN** the search field contains text and receives a cancel command
- **THEN** Lunchpad clears the query before any later Escape closes the launcher
