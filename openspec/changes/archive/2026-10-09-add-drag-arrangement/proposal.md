# Proposal: Drag arrangement of icons and folders

## Why

Lunchpad currently presents a fixed order derived from the selected automatic application
ordering. Users cannot arrange icons, group applications into folders, or move applications
between folders and the root, which are core interactions of the classic Launchpad being
restored.

## What Changes

- Add drag-to-rearrange within the visible container (root level or an open folder), including
  dropping onto empty grid slots.
- Add drag-to-create-folder: dropping an application onto another application creates a new
  logical folder at the target slot. Dropping an application onto an existing folder appends it
  to that folder.
- Add drag-to-remove: while a folder is open, dropping an application on the folder title moves
  it back to the root level.
- Add a `Manual` application ordering mode. The first drag switches the presentation order to
  Manual, seeded from the arrangement visible at drag time so the grid never scrambles.
- Persist every drag outcome transactionally in the layout database. The filesystem and `.app`
  bundles are never modified.

## Impact

- Affected specs: `logical-folders`
- Affected code: `LunchpadLayoutStore` (drag commit transactions), `ApplicationSortOrder` and
  `ApplicationOrderingPolicy` (manual mode), `IconGridView` and `LunchpadCollectionView`
  (drag gesture, feedback, and drop resolution), `AppDelegate` (commit handling).
- Out of scope for this change: folder rename and delete UI, dragging a folder onto another folder,
  and multi-item drag.
