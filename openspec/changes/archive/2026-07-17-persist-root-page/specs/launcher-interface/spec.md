## ADDED Requirements

### Requirement: Root page persistence across presentations

Lunchpad SHALL persist the last-viewed root-level page index and the time at which it was saved, and
SHALL restore that page on the next presentation when the saved time is within a bounded expiry. The
saved page SHALL be clamped to the currently valid page count on restore. When the saved value is
missing, invalid, or older than the expiry, Lunchpad SHALL present the first page. Only the
root-level page SHALL be persisted; folder pages remain transient.

#### Scenario: Reopen within the expiry restores the saved page

- **WHEN** the user pages to the second root page, closes Lunchpad, and reopens it a few seconds later
- **THEN** Lunchpad presents the second page instead of the first page

#### Scenario: Reopen after the expiry resets to the first page

- **WHEN** the saved root page is older than the expiry window at the time Lunchpad is shown
- **THEN** Lunchpad presents the first page

#### Scenario: Saved page exceeds the current page count

- **WHEN** Lunchpad is shown and the persisted page index is greater than the last valid page because
  applications were removed since the page was saved
- **THEN** Lunchpad clamps the restored page to the last valid page

#### Scenario: No saved page exists

- **WHEN** Lunchpad is shown for the first time or after stored data was cleared
- **THEN** Lunchpad presents the first page

#### Scenario: Stored page data is invalid

- **WHEN** the persisted page index or saved time is missing, the page index is negative, or the
  stored value is otherwise invalid
- **THEN** Lunchpad falls back to the first page without terminating or discarding unrelated valid
  preferences

#### Scenario: Closing inside a folder persists the root page

- **WHEN** the user enters a folder, hides Lunchpad, and reopens it within the expiry
- **THEN** Lunchpad presents the root page the user was on before entering the folder, not the
  folder's internal page

#### Scenario: Search result page is not persisted

- **WHEN** the user pages through multi-page search results and closes Lunchpad, then reopens it
- **THEN** Lunchpad clears the search and presents the first root page, not the previously viewed
  search-results page

#### Scenario: Persistence survives a process restart

- **WHEN** Lunchpad is quit and relaunched within the expiry window after a page was saved
- **THEN** the relaunched process restores the saved root page
