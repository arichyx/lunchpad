## ADDED Requirements

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
