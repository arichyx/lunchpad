## Context

Lunchpad previously treated the SQLite layout as folder-assignment storage while deriving the
visible application order from an automatic sorting preference. Drag arrangement changes that
relationship: a completed drag makes the visible order authoritative, persists it, and switches
the presentation to Manual without changing what the user sees.

The change crosses the AppKit interaction layer, pure drop planning, SQLite persistence,
filesystem reconciliation, application ordering, and the resident app lifecycle. The same
`LunchpadLayoutStore` is used by main-thread drag commits and by the catalog synchronizer's serial
background queue, so ordering and concurrency must be designed together rather than handled as
independent UI details.

## Goals / Non-Goals

**Goals:**

- Provide classic Launchpad drag behavior for root items and folder members while preserving
  click activation and fixed horizontal pages.
- Make every successful drop transactional and keep `.app` bundles untouched.
- Seed Manual mode from the complete arrangement the user was viewing, including when the first
  drag occurs inside a folder.
- Keep one stable root position namespace for applications and folders as applications are
  installed, removed, or rediscovered.
- Prevent a background catalog result from replacing a newer drag commit.
- Keep the launcher usable in flat fallback mode while disabling interactions that require
  persistent layout storage.

**Non-Goals:**

- Folder rename or delete UI.
- Nested folders, multi-item drag, or filesystem directory manipulation.
- Replacing AppKit collection views or the fixed paged grid with SwiftUI or a scrolling layout.

## Decisions

### Keep gesture resolution pure and persistence outcome-based

`GridDropLocator`, `DragPreview`, and `DragArrangementPlanner` operate on immutable container
snapshots and return a `LunchpadDragCommit`. AppKit owns pointer tracking and animation, while the
layout store owns validation and transactions. This keeps page geometry out of SQLite and makes
splice behavior independently testable.

Alternative considered: mutate the in-memory catalog continuously during pointer movement. That
would make cancellation, page turns, and catalog reloads depend on rollback logic and was rejected.

### Persist complete visible orders when entering Manual mode

Every drag outcome carries the complete order needed to preserve the visible presentation. Root
operations carry root slots directly. A folder reorder carries both the full member order and the
currently presented root slots, and the store applies both in one transaction. This prevents the
root page from reverting to an older stored order when the first drag occurs inside a folder under
Name, Creation Time, or Modification Time sorting.

Alternative considered: switch to Manual only for root-level drags. That would make the meaning of
Manual depend on where the first drag happened and would still lose the folder's visible order.

### Treat root applications and folders as one ordered namespace

Root `sort_position` values describe a single mixed sequence. When reconciliation discovers a new
root application, its starting position is after existing root applications and user folders, and
after the default Other folder when that folder is currently visible. The empty default folder's
large sentinel position is excluded so a fresh database still places normal applications before
Other. Unlisted hidden items retain their cross-type relative order when visible slots are rewritten.

Alternative considered: maintain independent application and folder counters and rely on names to
break equal positions. That makes installation reorder a manual layout and was rejected.

### Serialize high-level SQLite operations

`LunchpadLayoutStore` protects each public read or mutation with a recursive lock. SQLite's
`FULLMUTEX` mode protects individual C API calls but does not make a multi-statement transaction
atomic relative to another thread using the same connection. The high-level lock covers complete
transactions and layout reads; recursion is required because commit operations reuse existing
folder-assignment helpers.

Alternative considered: send drag commits synchronously through the catalog queue. A filesystem
scan can be slow, so blocking the main thread behind the whole scan would harm interaction latency.

### Rebase catalog callbacks on the latest persisted layout

Before applying a background catalog callback, `AppDelegate` reloads the current layout under the
store lock and reapplies the callback's scanner-derived dates and search aliases. A callback queued
before a drag can therefore refresh metadata without restoring its stale order. If the current
layout cannot be loaded, the callback is ignored and the existing UI remains intact.

Alternative considered: tag callbacks with only an FSEvents generation. A drag is not an FSEvent,
so that generation alone cannot distinguish a pre-drag snapshot delivered after the commit.

### Report persistent-layout capability from initial loading

The initial catalog result includes whether the synchronizer retained its layout store. If
reconciliation fails after the database was opened, `AppDelegate` drops its own store reference and
constructs the grid with drag arrangement disabled. This keeps fallback behavior consistent across
the synchronizer, commit handler, and UI.

## Risks / Trade-offs

- [Risk] A large reconciliation transaction can briefly delay a drop commit. → The filesystem scan
  remains outside the store lock; only SQLite reconciliation is serialized, and the busy timeout
  remains a final safeguard.
- [Risk] Hidden or temporarily absent items are not present in the drag snapshot. → The store
  appends unlisted root items in their existing mixed relative order and preserves assignments.
- [Risk] Collection-view reuse can retain an animated frame or transfer appearance. → Reloads
  normalize materialized cells, and cells reset transfer appearance during configuration.
- [Risk] A layout-only reload lacks scanner metadata. → Dates and search aliases are reapplied by
  stable application identifier before presentation.

## Migration Plan

No schema migration is required. Existing `sort_position`, `folder_id`, and `assignment_source`
columns already represent the needed state. Deployment consists of shipping the new interaction
and transaction code. Rolling back the binary leaves the database readable; older versions simply
ignore Manual presentation semantics while retaining folder assignments and positions.

## Open Questions

None for this change. Folder management UI and nested-folder policy remain explicitly out of scope.
