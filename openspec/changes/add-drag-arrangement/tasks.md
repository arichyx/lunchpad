# Tasks

## 1. Foundation

- [x] 1.1 Split `IconGridView.swift` into `LunchpadCollectionView.swift`, `LunchpadGridLayout.swift`, `PageIndicatorView.swift`, and `IconGridView.swift` without behavior changes
- [x] 1.2 Add `ApplicationSortOrder.manual`, identity handling in `ApplicationOrderingPolicy`, a Settings popup entry, and en/zh-Hans strings

## 2. Persistence

- [x] 2.1 Define `LunchpadRootSlot` and `LunchpadDragCommit` describing completed drag outcomes
- [x] 2.2 Implement `LunchpadLayoutStore.commit(_:)` with one transaction per outcome: root rearrange, folder rearrange, folder creation, folder addition, and removal to root
- [x] 2.3 Expose `loadVisibleItems()` so the delegate can reload the canonical arrangement after a commit

## 3. Drag interaction

- [x] 3.1 Add pure drop logic: splice index math, drop candidate locator, and arrangement planner
- [x] 3.2 Add drag gesture recognition to `LunchpadCollectionView` with click-semantics compatibility and scroll suppression while dragging
- [x] 3.3 Add drop feedback to `IconGridView`: lifted icon, folder-merge bubble, insertion-slot highlight, and remove-on-title highlight
- [x] 3.4 Wire drag commits through `LunchpadWindow` to `AppDelegate`, which persists, reloads the catalog, and switches to Manual ordering

## 4. Validation

- [x] 4.1 Test splice math, drop locator, and arrangement planner
- [x] 4.2 Test `LunchpadLayoutStore.commit(_:)` outcomes and reconcile interplay
- [x] 4.3 Test Manual ordering in `ApplicationOrderingPolicy`
- [x] 4.4 Run the full Swift test suite and `git diff --check`
- [x] 4.5 Update README known limitations

## 5. Drag feel

- [x] 5.1 Snapshot-based drag layer independent of collection-view cells
- [x] 5.2 Live gap preview keyed to on-screen cells with occupant-mapped drop targeting
- [x] 5.3 Settle animation into the final cell before the commit reload
- [x] 5.4 Edge page turning only beyond the grid bounds, with dwell and repeat cooldown
- [x] 5.5 Tests for the cell-occupant locator and preview slot mapping
- [x] 5.6 Translucent ghost placeholder at the insertion slot
- [x] 5.7 Merge hit area reduced to the icon artwork region; cell borders insert
- [x] 5.8 Insertion semantics unified on "lands at the hovered cell", fixing the forward-move
      off-by-one that dropped icons one cell short (and made the last column unreachable)
- [x] 5.9 Flip-aware merge hit rect (NSCollectionView is flipped), restoring folder creation
- [x] 5.10 Commit reloads replace the hidden origin cell instead of unhiding it first, removing
      the one-frame overlap flash at the old position
- [x] 5.11 Sticky merge targeting: hovering an icon's artwork holds the merge decision over its
      whole cell, so edge approach and release jitter cannot downgrade a merge into an insertion
- [x] 5.12 Merge area covers the full item cell (artwork plus label); insertion over an occupied
      cell snaps to the far-side boundary relative to the drag direction so the hovered icon
      never slides toward the pointer (headless end-to-end drag tests cover both directions)
- [x] 5.13 Forward cross-page insertion uses the cross-page gap mapping, keeps the ghost in the
      independent landing cell, and covers forward and backward page-turn regressions
- [x] 5.14 Invalidate delayed drag callbacks after catalog reloads and restore the hidden origin
      cell correctly when a drag returns to its source page
- [x] 5.15 Reapply scanner-derived dates and search aliases after a layout-only drag reload
- [x] 5.16 Preserve the remaining visible root order when an app joins an existing folder, within
      the same persistence transaction; disable drag arrangement in the flat-layout fallback
- [x] 5.17 Reset reused cell frames across drag page turns and reloads so outgoing preview
      animations cannot place two applications in the same cell
- [x] 5.18 Accept unchanged positions in valid drag transactions and preserve assignments for
      temporarily absent members when removing the last visible app from a user folder
- [x] 5.19 Preserve the push transition during drag page turns, keep the lifted icon continuous,
      and suppress only redundant drag labels when the snapshot overlaps a ghost or merge target
- [x] 5.20 Render a full-page backward cross-page preview overflow beyond the trailing page edge
      instead of placing the displaced application in a sixth grid row
- [x] 5.21 Present cross-page overflow as a dimmed, label-free partial icon at the corresponding
      screen edge in both directions, while preserving normal appearance when the preview closes
- [x] 5.22 Persist the currently presented root slots with a folder-member reorder so the first
      drag under automatic sorting switches to Manual without changing the root page
- [x] 5.23 Use one mixed root position namespace for reconciliation and preserve unlisted
      application/folder order, with a trailing-folder new-application regression test
- [x] 5.24 Propagate initial persistent-layout fallback to `AppDelegate` so flat mode really
      disables drag arrangement
- [x] 5.25 Serialize high-level layout-store access and rebase background catalog callbacks on the
      latest persisted layout so a stale refresh cannot overwrite a drag commit
- [x] 5.26 Add the cross-cutting design artifact, move `dev-run.sh` documentation to the
      Development section, and rerun focused/full validation
