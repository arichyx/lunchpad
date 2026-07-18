## Why

Lunchpad currently searches only the localized name shown below an application icon, so a user
whose system displays “计算器” cannot find it by typing its familiar bundle name, “Calculator.”
Searching both names aligns the launcher more closely with the system Launchpad behavior without
changing the localized name presented in the grid.

## What Changes

- Capture an application's nonlocalized bundle display name and bundle name as in-memory search
  aliases while preserving the existing localized display-name selection.
- Match a trimmed, case-insensitive substring query against both the displayed name and the
  deduplicated bundle-name aliases.
- Continue showing each matching application once under its localized display name, regardless of
  which name matched.
- Include search-alias changes in catalog refresh detection and cover localized-name and
  bundle-name matches with focused tests.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `application-catalog`: Discovered applications expose bundle-provided name aliases for in-memory
  search in addition to their localized display name.
- `launcher-interface`: Application search matches the displayed name or a bundle-provided name
  alias while preserving existing result presentation and activation behavior.

## Impact

The change affects application metadata discovery in `AppScanner`, the `AppItem` in-memory model,
catalog change signatures, and filtering in `IconGridView`. It may add a small pure search-matching
helper and focused scanner/search tests. No database migration, new dependency, network access, or
user-facing setting is required.
