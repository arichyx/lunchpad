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
- **AND** they take the folder's former place in the root order, keeping their order within the folder

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

#### Scenario: A refresh finds the same applications

- **WHEN** reconciliation discovers the same applications with unchanged identity, name, and path
- **THEN** Lunchpad does not write to the layout database

#### Scenario: Schema is upgraded

- **WHEN** Lunchpad opens a layout database whose recorded schema version is older than the version it supports
- **THEN** it applies each upgrade step in its own transaction and records the new version without losing assignments or positions

#### Scenario: Database was written by a newer build

- **WHEN** the recorded schema version is newer than the version this build supports
- **THEN** Lunchpad leaves the database unmodified and uses the flat-layout fallback

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

### Requirement: Folder rename and deletion

Lunchpad SHALL let the user rename and delete user folders from the launcher while a persistent
layout is available. The protected Other folder and the flat fallback layout SHALL offer neither
action.

#### Scenario: User renames an open folder

- **WHEN** a user folder is open and the user clicks its title, edits it, and presses Return or clicks elsewhere
- **THEN** Lunchpad stores the trimmed name and presents it without leaving the folder

#### Scenario: User abandons a rename

- **WHEN** the user presses Escape while editing a folder title, or submits an empty or unchanged name
- **THEN** the previous name is kept, and a further Escape leaves the folder as usual

#### Scenario: User opens a folder's context menu

- **WHEN** the user secondary-clicks a user folder on the root page
- **THEN** Lunchpad offers Rename Folder, which opens the folder with its title ready for editing, and Delete Folder, which deletes the logical folder

#### Scenario: Context menu on other items

- **WHEN** the user secondary-clicks an application, the Other folder, a search result, or any item in the flat fallback layout
- **THEN** Lunchpad shows no folder menu

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

### Requirement: Drag arrangement

Lunchpad SHALL let the user arrange icons by dragging within the visible container: the root
level, or the contents of an open folder. Drag outcomes SHALL be persisted as logical-folder
assignments and sort positions, and SHALL NOT create, move, or delete filesystem directories or
`.app` bundles.

#### Scenario: Icon is dragged to an empty slot

- **WHEN** an icon is dragged from one grid slot and released over an empty slot or a gap between icons
- **THEN** the icon occupies the released position in the container order and the persisted sort positions reflect the new arrangement

#### Scenario: Drop position is previewed live

- **WHEN** an icon is dragged over the grid
- **THEN** the other icons animate to open a gap at the position a release would commit, a translucent ghost of the icon occupies that gap, and the released icon settles into it before the persisted arrangement is applied
- **AND** when a full page displaces an application across a page boundary, that application appears dimmed, without its name, and partially visible at the corresponding screen edge

#### Scenario: Insertion and folder creation are distinguishable

- **WHEN** the dragged icon hovers directly over another icon's artwork
- **THEN** Lunchpad shows a merge bubble and a release creates or joins a folder
- **WHEN** the dragged icon hovers anywhere else in a cell, including beside or between icons
- **THEN** the drop resolves as an insertion at that position

#### Scenario: Drag hovers a screen edge

- **WHEN** the dragged icon is pushed beyond the grid into the outer screen-edge padding and held there briefly while another page exists
- **THEN** Lunchpad turns to the adjacent page and the drag continues onto it
- **AND** hovering anywhere inside the grid, including the bordering last column, never turns the page

#### Scenario: Application is dropped onto another application

- **WHEN** an application icon is released over a different application icon at the root level
- **THEN** Lunchpad creates a new logical folder at the target slot containing both applications and no `.app` bundle is modified

#### Scenario: Application is dropped onto a folder

- **WHEN** an application icon is released over a logical folder at the root level
- **THEN** the application is appended to that folder's membership

#### Scenario: Application is dragged out of an open folder

- **WHEN** an application icon inside an open folder is released over the folder title
- **THEN** the application returns to the root level next to the folder and a user folder that becomes empty is deleted

#### Scenario: Drag is released without a target

- **WHEN** a drag is released over the dragged item's own slot, the search field, or while search results are shown
- **THEN** the arrangement is unchanged and the interaction falls back to click semantics

#### Scenario: Persistent layout falls back during initial loading

- **WHEN** the layout database opens but initial reconciliation cannot produce a persistent catalog
- **THEN** Lunchpad presents the flat catalog and disables drag arrangement for that process

#### Scenario: Catalog synchronization overlaps a drag commit

- **WHEN** a background application-directory refresh overlaps a successful drag commit
- **THEN** database operations remain atomic and a refresh delivered after the commit preserves the committed arrangement while applying current scanner metadata

### Requirement: Manual ordering mode

Lunchpad SHALL provide a Manual application ordering mode in which the presented order is the
persisted sort position order. When the user completes a drag arrangement while an automatic
ordering mode is selected, Lunchpad SHALL switch the presentation order to Manual without
visibly re-sorting the grid.

#### Scenario: First drag while automatic ordering is selected

- **WHEN** a drag is committed while Name, Creation Time, or Modification Time ordering is selected
- **THEN** Lunchpad persists the visible arrangement including the drag outcome and selects Manual ordering

#### Scenario: First drag occurs inside a folder

- **WHEN** the first drag under an automatic ordering mode rearranges applications inside an open folder
- **THEN** Lunchpad persists both the folder's visible member order and the currently presented root order in the same transaction before selecting Manual

#### Scenario: New application follows a mixed manual layout

- **WHEN** a new root application is discovered after a manual arrangement whose last visible item is a folder
- **THEN** the new application is appended after that folder without changing the existing mixed application-and-folder order

#### Scenario: Automatic ordering is selected again

- **WHEN** the user selects an automatic ordering mode after arranging manually
- **THEN** the presented order is derived from that mode while every persisted assignment and sort position is preserved
