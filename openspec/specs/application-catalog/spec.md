# Application Catalog Specification

## Purpose

Define how Lunchpad discovers installed applications, chooses their displayed identity, and
keeps the visible catalog synchronized with filesystem changes without exposing incomplete app
copies.

## Requirements

### Requirement: Application discovery roots

Lunchpad SHALL discover application bundles recursively under `~/Applications`, `/Applications`, and `/System/Applications` when those roots exist.

#### Scenario: Discover an installed application

- **WHEN** a valid `.app` bundle exists below a configured application root
- **THEN** Lunchpad includes the application in its catalog regardless of intermediate Finder directories

#### Scenario: Ignore nested package contents

- **WHEN** an application bundle contains nested directories or nested bundles
- **THEN** Lunchpad treats the outer `.app` as one application and does not expose its package contents as independent root items

### Requirement: Complete bundle validation

Lunchpad SHALL expose an application only after its `Contents/Info.plist` identifies a main executable and that executable exists on disk.

#### Scenario: App copy is still in progress

- **WHEN** Finder has created a `.app` directory but its Info.plist or main executable is not yet present
- **THEN** Lunchpad excludes it from the catalog until a later stable scan finds a complete bundle

### Requirement: Stable application identity

Lunchpad SHALL identify an application by its lowercased bundle identifier when available and by its canonical filesystem path otherwise.

#### Scenario: Application moves without changing bundle identifier

- **WHEN** a previously known application is discovered at a new path with the same bundle identifier
- **THEN** Lunchpad updates its path and preserves the existing logical layout identity

#### Scenario: Duplicate discovery

- **WHEN** multiple discovered paths resolve to the same application identity
- **THEN** Lunchpad includes that identity only once in the reconciled catalog

### Requirement: Localized application names

Lunchpad SHALL display the application name for the user's preferred language when the bundle provides localized metadata.

#### Scenario: Localized InfoPlist table is available

- **WHEN** the application provides a preferred-language `InfoPlist.loctable` or `InfoPlist.strings` value
- **THEN** Lunchpad uses its localized `CFBundleDisplayName` or `CFBundleName`

#### Scenario: Localized metadata is unavailable

- **WHEN** no localized Info.plist name can be resolved
- **THEN** Lunchpad falls back through the localized filesystem name, raw bundle display name, raw bundle name, and filename without the `.app` extension

### Requirement: Stable filesystem synchronization

Lunchpad SHALL treat FSEvents as invalidation signals and SHALL reconcile the catalog only after the application filesystem reaches a stable state.

#### Scenario: A copy produces repeated writes

- **WHEN** one install, move, replacement, or removal produces a burst of filesystem events
- **THEN** Lunchpad waits for a quiet period and two identical bundle snapshots before reconciling the catalog

#### Scenario: Events arrive during reconciliation

- **WHEN** a newer filesystem event arrives while a scan is in progress
- **THEN** Lunchpad discards the stale scan result and performs stability checking for the newer event generation

#### Scenario: FSEvents reports dropped history

- **WHEN** FSEvents reports dropped events, wrapped identifiers, or a required subtree rescan
- **THEN** Lunchpad performs a recovery scan and invalidates the full icon cache

#### Scenario: A monitored root moves or disappears

- **WHEN** FSEvents reports that a watched root changed
- **THEN** Lunchpad rebuilds the stream from the nearest existing ancestor and performs a recovery scan

### Requirement: Nonfatal catalog failure

Catalog or layout persistence failures SHALL NOT terminate the resident Lunchpad process.

#### Scenario: SQLite is unavailable during initial loading

- **WHEN** the layout database cannot be opened or reconciled
- **THEN** Lunchpad displays a flat application catalog without inferred logical folders

#### Scenario: A background reconciliation fails

- **WHEN** a later catalog refresh encounters an error
- **THEN** Lunchpad preserves the current interface and waits for a subsequent filesystem event to retry
