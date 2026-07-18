## ADDED Requirements

### Requirement: Active Space change dismissal

Lunchpad SHALL close the visible launcher through its normal dismissal path when macOS reports that
the active Space changed. This dismissal SHALL preserve the reusable launcher windows, resident
process, catalog monitoring, activation controls, and saved root-page behavior.

#### Scenario: User changes Space while launcher is visible

- **WHEN** the launcher is visible and macOS reports an active Space change
- **THEN** Lunchpad begins its normal close animation and remains available for later activation

#### Scenario: Space changes while launcher is hidden

- **WHEN** the launcher is hidden and macOS reports an active Space change
- **THEN** Lunchpad remains hidden and its resident monitors continue running

#### Scenario: Space change races with another dismissal

- **WHEN** macOS reports an active Space change after another event has already started closing the
  launcher
- **THEN** Lunchpad completes one dismissal without reopening, terminating, or starting a second
  conflicting close transition
