## ADDED Requirements

### Requirement: Bundle-provided application search aliases

Lunchpad SHALL retain each application's nonempty raw `CFBundleDisplayName` and `CFBundleName` as
deduplicated search aliases without changing the localized name displayed to the user.

#### Scenario: Localized and raw bundle names differ

- **WHEN** an application resolves to the localized display name “计算器” and its raw bundle name is
  “Calculator”
- **THEN** Lunchpad retains “Calculator” as a search alias and continues displaying “计算器”

#### Scenario: Raw bundle names duplicate the displayed name or each other

- **WHEN** an application's raw bundle display name and bundle name are empty or duplicate another
  searchable name case-insensitively
- **THEN** Lunchpad ignores the empty or duplicate values instead of retaining redundant aliases
