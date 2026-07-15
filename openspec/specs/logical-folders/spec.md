# Logical Folders Specification

## Purpose

Define Lunchpad's persistent logical grouping model, the protected Other folder, and folder-level
navigation independently of Finder directories.

## Requirements

### Requirement: Logical grouping independence

Lunchpad folders SHALL represent database-backed relationships and SHALL NOT represent or modify filesystem directories.

#### Scenario: App is assigned to a logical folder

- **WHEN** Lunchpad stores an application-folder assignment
- **THEN** the `.app` bundle remains at its original filesystem path

#### Scenario: Logical folder is deleted

- **WHEN** a non-system folder is deleted
- **THEN** its member applications return to the root layout without moving or deleting their `.app` bundles

### Requirement: Persistent layout database

Lunchpad SHALL persist folder metadata, application identity, current paths, assignments, and sort positions in `~/Library/Application Support/com.arichyx.Lunchpad/layout.sqlite3`.

#### Scenario: Lunchpad restarts

- **WHEN** applications still present on disk are reconciled after relaunch
- **THEN** their persisted root or folder assignments and relative sort positions are restored

#### Scenario: Application is removed and later returns

- **WHEN** a known identity is temporarily absent and is later rediscovered
- **THEN** Lunchpad marks it visible again while preserving its existing layout assignment

### Requirement: Protected Other folder

Lunchpad SHALL seed a protected system folder named Other and SHALL localize its displayed name as `其他` for Chinese preferred languages.

#### Scenario: First database initialization

- **WHEN** the layout database is created
- **THEN** Lunchpad creates the protected `system.other` folder

#### Scenario: Other folder is empty

- **WHEN** no present application belongs to Other
- **THEN** Lunchpad omits the empty folder from the visible root layout

#### Scenario: System folder mutation is requested

- **WHEN** a caller attempts to rename or delete the protected Other folder
- **THEN** the layout store rejects the operation

### Requirement: Default utility assignment

Lunchpad SHALL initially assign applications discovered under `/Applications/Utilities` or `/System/Applications/Utilities` to Other unless a user-controlled assignment already exists.

#### Scenario: New utility is discovered

- **WHEN** an application under a Utilities root has no stored assignment
- **THEN** Lunchpad appends it to Other with a default assignment source

#### Scenario: User previously moved an application

- **WHEN** an application's stored assignment source is user-controlled
- **THEN** later scans do not return it to Other based on its filesystem path

### Requirement: Folder membership operations

Each application SHALL belong to at most one logical folder, and a user assignment to `nil` SHALL place it at the root.

#### Scenario: Application is reassigned

- **WHEN** an application is assigned to another valid folder
- **THEN** Lunchpad replaces its previous membership and appends it to the destination order

#### Scenario: Invalid folder is requested

- **WHEN** an assignment references a folder that does not exist
- **THEN** the layout store rejects the assignment without modifying the existing relationship

### Requirement: Full-page folder navigation

Opening a folder SHALL replace the root page with the folder's paged application contents rather than presenting a floating overlay.

#### Scenario: User opens a folder

- **WHEN** a root-level folder item is activated
- **THEN** Lunchpad saves the current root page, hides search, shows the folder title, and opens the folder at page zero

#### Scenario: User exits a folder

- **WHEN** the user presses Escape or clicks empty space while a folder is open
- **THEN** Lunchpad returns to the previously visible root page instead of closing

#### Scenario: Open folder disappears during synchronization

- **WHEN** a catalog refresh no longer contains the currently open folder
- **THEN** Lunchpad returns to the root level and keeps the launcher visible
