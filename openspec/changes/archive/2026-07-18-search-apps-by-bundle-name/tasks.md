## 1. Application Metadata

- [x] 1.1 Extend `AppItem` and `AppScanner` to retain trimmed, case-insensitively deduplicated raw
  `CFBundleDisplayName` and `CFBundleName` search aliases without changing display-name resolution.
- [x] 1.2 Propagate search aliases through reconciled-catalog enrichment and flat fallback
  construction without adding a SQLite migration.
- [x] 1.3 Include deterministically ordered search aliases in catalog signatures so alias-only
  application updates refresh the UI.

## 2. Search Behavior

- [x] 2.1 Add a pure, in-memory matcher for trimmed, case-insensitive substring queries across an
  application's displayed name and search aliases.
- [x] 2.2 Use the shared matcher for both live query changes and catalog refreshes during an active
  search while preserving result order, localized labels, and one result per application.

## 3. Tests and Documentation

- [x] 3.1 Extend scanner fixtures to verify a localized display name retains distinct raw bundle
  names as aliases and ignores empty or duplicate aliases.
- [x] 3.2 Add focused matcher tests for localized-name matches, bundle-name matches,
  case-insensitive substrings, nonmatches, and applications whose multiple names match one query.
- [x] 3.3 Update the README search feature description to mention localized and bundle-name search.
- [x] 3.4 Run `swift test --package-path /Users/arichyx/proj/arichyx/personal/lunchpad` and
  `git diff --check`.
