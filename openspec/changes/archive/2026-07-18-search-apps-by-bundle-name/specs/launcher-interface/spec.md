## MODIFIED Requirements

### Requirement: Application search

Lunchpad SHALL filter all discovered applications by localized display name or bundle-provided
search alias using a trimmed, case-insensitive substring query. Each matching application SHALL
appear once under its localized display name. Return or keypad Enter SHALL activate the
keyboard-active result when one exists and otherwise SHALL launch the first matching application.

#### Scenario: User enters a query

- **WHEN** search text changes at the root level
- **THEN** Lunchpad resets to page zero and displays matching applications without folder wrappers

#### Scenario: Query matches the localized display name

- **WHEN** the trimmed query is a case-insensitive substring of an application's localized display
  name
- **THEN** Lunchpad includes that application in the search results

#### Scenario: Query matches a bundle-provided name alias

- **WHEN** an application is displayed as “计算器” with the bundle-provided search alias
  “Calculator” and the user searches for “calculator”
- **THEN** Lunchpad includes the application once and continues labeling it “计算器”

#### Scenario: More than one searchable name matches

- **WHEN** the query matches both an application's localized display name and one or more of its
  bundle-provided search aliases
- **THEN** Lunchpad includes that application only once in its existing catalog order

#### Scenario: Search has no results

- **WHEN** neither an application display name nor any of its bundle-provided search aliases
  contains the query
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
