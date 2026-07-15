## MODIFIED Requirements

### Requirement: Persistent layout database
Lunchpad SHALL persist folder metadata, application identity, current paths, assignments, and sort
positions in `~/Library/Application Support/com.arichyx.Lunchpad/layout.sqlite3`. Preference-driven
application ordering SHALL be a reversible presentation transform and SHALL NOT rewrite these
persisted assignments or positions.

#### Scenario: Lunchpad restarts
- **WHEN** applications still present on disk are reconciled after relaunch
- **THEN** their persisted root or folder assignments and canonical relative sort positions are restored before the selected presentation ordering is applied

#### Scenario: Application is removed and later returns
- **WHEN** a known identity is temporarily absent and is later rediscovered
- **THEN** Lunchpad marks it visible again while preserving its existing layout assignment

#### Scenario: Automatic ordering is changed
- **WHEN** the user switches among Name, Creation Time, and Modification Time ordering
- **THEN** Lunchpad derives a new visible app order while preserving every stored assignment and sort position

### Requirement: Protected Other folder
Lunchpad SHALL seed a protected system folder named Other and SHALL display its localized name using
the resolved Lunchpad interface language.

#### Scenario: First database initialization
- **WHEN** the layout database is created
- **THEN** Lunchpad creates the protected `system.other` folder with a language-neutral system identity

#### Scenario: Other folder is empty
- **WHEN** no present application belongs to Other
- **THEN** Lunchpad omits the empty folder from the visible root layout

#### Scenario: System folder mutation is requested
- **WHEN** a caller attempts to rename or delete the protected Other folder
- **THEN** the layout store rejects the operation

#### Scenario: Interface language changes
- **WHEN** the resolved interface language changes between English and Simplified Chinese
- **THEN** the protected folder displays as `Other` or `其他` without modifying its stored identity or assignments
