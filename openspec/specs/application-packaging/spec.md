# Application Packaging Specification

## Purpose

Define the reproducible release bundle produced from the Swift Package Manager executable without
requiring an Xcode project or Apple Developer account.

## Requirements

### Requirement: Release app bundle

The packaging workflow SHALL build the release `Lunchpad` product and assemble a standard macOS application bundle at `dist/Lunchpad.app`.

#### Scenario: Packaging succeeds

- **WHEN** `Scripts/package-app.sh` runs with a working Swift and Xcode command-line toolchain
- **THEN** it places the executable in `Contents/MacOS` and places Info.plist, AppIcon.icns, and the software license in their standard bundle locations

#### Scenario: Release executable is missing

- **WHEN** SwiftPM does not produce an executable at the resolved release binary path
- **THEN** the packaging workflow fails instead of creating an incomplete app bundle

### Requirement: Bundle identity

The packaged application SHALL declare display name and executable `Lunchpad`, bundle identifier `com.arichyx.Lunchpad`, minimum macOS version 26.0, and accessory-app behavior.

#### Scenario: Finder or Launch Services inspects the bundle

- **WHEN** macOS reads the packaged Info.plist
- **THEN** it resolves the Lunchpad executable, multi-resolution icon, application category, single-instance policy, and `LSUIElement` accessory behavior

### Requirement: Configurable release version

The packaging workflow SHALL accept stable or SemVer prerelease `VERSION` values and numeric
`BUILD_NUMBER` values while defaulting to version `0.1.0` and build `1`. Distribution artifacts
SHALL retain the complete release version, while `CFBundleShortVersionString` SHALL contain only
the numeric `MAJOR.MINOR.PATCH` component.

#### Scenario: Version metadata is supplied

- **WHEN** packaging runs with stable version `0.1.1` and a numeric build value
- **THEN** the generated bundle Info.plist contains those values without modifying the source plist

#### Scenario: Prerelease metadata is supplied

- **WHEN** packaging runs with version `0.1.1-beta.1`
- **THEN** artifact names contain `0.1.1-beta.1` and the generated bundle declares `CFBundleShortVersionString` as `0.1.1`

#### Scenario: Version metadata is invalid

- **WHEN** `VERSION` is neither `MAJOR.MINOR.PATCH` nor a supported SemVer prerelease, or `BUILD_NUMBER` contains non-digit characters
- **THEN** packaging fails before creating release artifacts

### Requirement: Ad-hoc signature verification

The packaging workflow SHALL apply and verify an ad-hoc code signature without requiring an Apple Developer identity.

#### Scenario: Bundle contents are complete

- **WHEN** executable, plist, and resources have been copied
- **THEN** the workflow signs the bundle with identity `-` and fails if strict verification does not pass

#### Scenario: User downloads the build on another Mac

- **WHEN** Gatekeeper assigns quarantine to the unsigned-identity distribution
- **THEN** the user may need to approve the trusted build manually because ad-hoc signing does not provide notarization

### Requirement: Versioned distribution artifacts

The packaging workflow SHALL create versioned arm64 DMG and ZIP artifacts plus a SHA-256 checksum manifest.

#### Scenario: Packaging completes

- **WHEN** version `0.1.0` finishes packaging
- **THEN** `dist` contains `Lunchpad-0.1.0-macos-arm64.dmg`, `Lunchpad-0.1.0-macos-arm64.zip`, and `SHA256SUMS.txt`

#### Scenario: User opens the DMG

- **WHEN** the release DMG is mounted
- **THEN** it contains `Lunchpad.app`, an Applications symlink, and the software license

### Requirement: Release package verification

The repository SHALL provide a verification workflow that checks bundle metadata, architecture, code signature, archive checksums, and mounted DMG contents.

#### Scenario: Release artifacts are valid

- **WHEN** `Scripts/verify-package.sh` runs with the same `VERSION` used for packaging
- **THEN** it verifies the app and every distribution artifact without modifying them

#### Scenario: A release artifact is incomplete

- **WHEN** an expected artifact, Applications symlink, license, signature, or checksum is missing or invalid
- **THEN** verification fails before the release can be published

### Requirement: Tag-driven draft release

The GitHub release workflow SHALL build a draft release from a stable or SemVer prerelease tag
contained in the `main` branch history.

#### Scenario: A valid release tag is pushed

- **WHEN** a valid annotated release tag pointing into `main` is pushed to GitHub
- **THEN** CI tests, packages, verifies, and uploads the DMG, ZIP, and checksum manifest to a Draft GitHub Release

#### Scenario: A prerelease tag is pushed

- **WHEN** a tag such as `v0.1.1-beta.1` is pushed from `main`
- **THEN** the workflow creates a Draft GitHub Release marked as a prerelease and retains the complete version in every asset name

#### Scenario: A release tag is invalid

- **WHEN** a pushed tag has an unsupported version form or points outside `main`
- **THEN** the release workflow fails without creating a public release

#### Scenario: A published release already exists

- **WHEN** the workflow is rerun for a tag whose release is already public
- **THEN** it refuses to replace the published assets
