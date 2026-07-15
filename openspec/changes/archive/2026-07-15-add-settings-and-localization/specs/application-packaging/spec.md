## ADDED Requirements

### Requirement: Packaged localization resources
The packaging workflow SHALL include the SwiftPM resource bundle containing complete English and
Simplified Chinese localizations at the runtime path expected by the executable, and package
verification SHALL validate both localizations.

#### Scenario: Release app is assembled
- **WHEN** `Scripts/package-app.sh` copies the release executable into `Lunchpad.app`
- **THEN** it also copies the executable target's processed resource bundle containing `en` and `zh-Hans` localization tables before code signing

#### Scenario: Localization resources are missing
- **WHEN** the processed resource bundle or either required localization table cannot be found
- **THEN** packaging fails instead of producing an English-only or partially localized application

#### Scenario: Release package is verified
- **WHEN** `Scripts/verify-package.sh` validates the assembled app, ZIP, and DMG
- **THEN** it confirms that both required localization tables are sealed inside each packaged application bundle
