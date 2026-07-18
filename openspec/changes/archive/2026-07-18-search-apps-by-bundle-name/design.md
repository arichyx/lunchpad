## Context

`AppScanner` currently resolves one localized display name for each application and discards the
other name values read from its raw `Info.plist`. `AppItem` therefore carries only that displayed
name, and both search filtering paths in `IconGridView` match only `AppItem.name`. For example,
Calculator's raw bundle names are “Calculator” while its preferred `InfoPlist.loctable` display
name is “计算器”, so the English query cannot match on a Chinese system.

Application metadata is already scanned off the high-frequency UI path. When SQLite is available,
the scanner reconciles the catalog through `LunchpadLayoutStore` and then enriches the returned
items with transient filesystem dates. Catalog signatures decide whether a completed rescan needs
to refresh the UI.

## Goals / Non-Goals

**Goals:**

- Make a query match the current localized display name, raw `CFBundleDisplayName`, or raw
  `CFBundleName`.
- Keep the localized display name as the only name shown under the icon.
- Keep search filtering in memory and preserve current result order, paging, and activation.
- Refresh an active search when an application's searchable aliases change.
- Cover alias discovery and matching with focused tests.

**Non-Goals:**

- Searching bundle identifiers, executable names, paths, or every localization contained in an
  application bundle.
- Changing display-name resolution, application ordering, or the Lunchpad interface language.
- Adding fuzzy, tokenized, transliterated, or pinyin search.
- Persisting derived aliases or introducing a database migration.

## Decisions

### Carry deduplicated raw bundle names as transient search aliases

Extend `AppItem` with an immutable collection of search aliases populated from nonempty raw
`CFBundleDisplayName` and `CFBundleName` values in the application's main `Info.plist`. Trim and
deduplicate aliases case-insensitively, including against the resolved display name, so the common
case does not perform redundant comparisons.

The aliases remain derived scanner output. The existing post-reconciliation enrichment step will
copy them from discovered items onto items loaded from SQLite, just as it already does for
filesystem dates; the flat-layout fallback already uses scanner items directly. This avoids
storing rebuildable metadata and avoids a schema migration.

Alternatives considered:

- Persist aliases in SQLite. This would let store-only reads retain them, but all visible catalogs
  already originate from a scan and reconciliation, so persistence adds migration and consistency
  costs without improving the current lifecycle.
- Use the bundle identifier or executable name as an alias. Those values are often implementation
  details and exceed the requested system-like name search.
- Index every localized Info.plist table entry. This increases memory and creates surprising
  cross-language matches; only the current display name and nonlocalized bundle names are in scope.

### Centralize matching and use it in both filtering paths

Introduce one pure application-search matcher, either on `AppItem` or as a small policy type. It
will test the trimmed query against the displayed name and aliases with the existing
locale-aware, case-insensitive substring semantics. Both live text changes and catalog refreshes
while a query is active must call this matcher instead of duplicating predicates.

The filter continues to iterate each `AppItem` once and emit that item at most once, so matching
multiple names cannot duplicate a result. It preserves `allApps` order and never touches bundles,
the filesystem, Launch Services, or SQLite while the user types.

Alternatives considered:

- Concatenate all names into one search string. Separate comparisons avoid accidental matches that
  span name boundaries and keep the matching contract explicit.
- Re-resolve bundle metadata during each query. That would violate the lightweight
  high-frequency AppKit path and add avoidable latency.

### Treat alias changes as catalog metadata changes

Add aliases in deterministic order to `ApplicationCatalogSynchronizer`'s catalog signature.
Otherwise a replacement application whose path and displayed name remain unchanged but whose raw
bundle name changes would not refresh an active search. Alias metadata does not affect icon-cache
invalidation beyond the synchronizer's existing filesystem-event behavior.

### Test discovery and search separately

Extend scanner fixtures to verify that localized display-name resolution retains a distinct raw
bundle name as an alias. Add pure matcher tests for display-name matches, bundle-name matches,
case-insensitive substrings, nonmatches, and the single-result behavior when more than one name
matches. This keeps AppKit UI tests unnecessary for the matching contract.

## Risks / Trade-offs

- [Some applications use technical raw bundle names] → Limit aliases to the two standard
  user-facing Info.plist name keys and continue displaying only the localized name.
- [Transient aliases could be lost when reconstructing stored items] → Make scanner enrichment
  explicit and test both reconciled and flat catalog paths where practical.
- [Duplicated filtering code could drift again] → Route both query application sites through the
  same matcher.
- [Additional comparisons run on each keystroke] → Deduplicate aliases during scanning and keep all
  comparisons in memory; the bounded number of short names per application makes the cost small.

## Migration Plan

No data migration is needed. Existing databases remain compatible because aliases are regenerated
on every application scan. Rollback consists of removing the transient field and matcher; stored
layout data is unaffected.

## Open Questions

None.
