## 1. Preferences and Localization Foundation

- [x] 1.1 Implement typed interface-language, application-order, gesture-intent, and shortcut preference values in the `com.arichyx.Lunchpad` defaults domain, including independent invalid-value fallback and legacy string hot-key migration.
- [x] 1.2 Add an injectable localization service with Follow System resolution, explicit English and Simplified Chinese selection, English key fallback, and runtime change notifications.
- [x] 1.3 Add complete `en.lproj` and `zh-Hans.lproj` Localizable resources for current menus, search and empty states, protected folder text, accessibility labels, settings controls, validation, and actionable errors.
- [x] 1.4 Add focused tests for preference defaults, malformed stored data, legacy shortcut migration, supported-language resolution, and missing-key fallback.

## 2. Non-Destructive Application Ordering

- [x] 2.1 Attach application-bundle creation and modification dates to discovered `AppItem` values and re-enrich SQLite-reconciled items by stable identity without changing the layout schema.
- [x] 2.2 Include both dates in catalog change detection so bundle replacement or update can refresh time-based ordering.
- [x] 2.3 Implement Name, Creation Time, and Modification Time ordering with deterministic tie-breakers, folder-member sorting, and root app-slot reinsertion that preserves folder positions.
- [x] 2.4 Retain the latest canonical catalog in the main-actor coordinator and reapply ordering from cached data when order or collation language changes, without rescanning or rewriting SQLite positions.
- [x] 2.5 Add tests for all three sort modes, unknown dates, equal-key tie-breakers, per-folder ordering, root folder-slot preservation, and unchanged persisted layout positions.
- [x] 2.6 Add filesystem Creation Time throughout discovery and presentation without resetting the user's selected ordering.
- [x] 2.7 Restore Modification Time as a separate option alongside Creation Time and preserve both persisted enum values independently.

## 3. Conflict-Safe Global Shortcuts

- [x] 3.1 Generalize `HotKeyConfiguration` to validated hardware key codes and Carbon modifier bits with normalized macOS glyph display and an explicit disabled state.
- [x] 3.2 Refactor Carbon registration behind an injectable registrar, assign unique event IDs, and implement candidate-first replacement that preserves the old registration and stored preference on every failure.
- [x] 3.3 Preserve `LUNCHPAD_HOTKEY` as a documented development override and expose its externally managed state to Settings without allowing misleading edits.
- [x] 3.4 Build the AppKit shortcut recorder with recording, cancel, clear, supported function keys, modifier validation, and localized conflict or registration feedback.
- [x] 3.5 Add unit tests for recorder validation, shortcut encoding/display, available and conflicting candidate swaps, no-op replacement, clearing, startup failure state, and development override precedence.

## 4. Native Settings and Live Interface Refresh

- [x] 4.1 Build a reusable programmatic AppKit Settings window with Appearance and Activation groups for Language, Application Order, Shortcut, Launch at Login, and Four-Finger Pinch.
- [x] 4.2 Add localized Settings... commands to the right-click status menu and application menu with Command-Comma, preserving left-click launcher activation, explicit Quit, accessory policy, and single-window behavior.
- [x] 4.3 Coordinate launcher and Settings presentation so opening either orders out the other without terminating the resident process or disturbing catalog monitoring.
- [x] 4.4 Replace hard-coded Lunchpad-owned strings and accessibility descriptions in menus, launcher search and empty states, protected Other folder presentation, Settings, and actionable errors with localization keys.
- [x] 4.5 Implement a main-actor localization refresh that rebuilds menus and refreshes retained Settings and launcher views immediately while preserving the current valid folder, search, and page state.
- [x] 4.6 Keep the reusable Settings window on the currently active macOS Space and add regression coverage for its window collection behavior.
- [x] 4.7 Label the Simplified Chinese language choice as `Chinese` when the Settings interface is English.
- [x] 4.8 Label the Simplified Chinese language choice as `中文` when the Settings interface is Chinese.

## 5. Resident Behavior Controls

- [x] 5.1 Wrap `SMAppService.mainApp` behind an injectable login-item service that reads system status, registers or unregisters on demand, rolls the UI back on failure, and disables the control for raw SwiftPM executables.
- [x] 5.2 Refactor multitouch monitor lifecycle so the stored Four-Finger Pinch intent controls startup, runtime disable stops and clears the monitor, and runtime enable creates a fresh monitor.
- [x] 5.3 Surface login-item failures and enabled-but-unavailable gesture state in Settings while keeping status-item and available hot-key activation operational.
- [x] 5.4 Add adapter tests for login-item status/error rollback and gesture enable, disable, pending-sequence cancellation, failure reporting, and retry behavior without mutating real system registrations.

## 6. Packaging, Documentation, and Verification

- [x] 6.1 Update SwiftPM resource declarations and `Scripts/package-app.sh` to locate and copy the generated Lunchpad resource bundle before signing, failing when either required localization is absent.
- [x] 6.2 Update `Scripts/verify-package.sh` to verify English and Simplified Chinese localization tables in the assembled app, an extracted ZIP, and the mounted DMG.
- [x] 6.3 Update README documentation for Settings access, language and ordering semantics, hot-key conflict limits and clearing, Launch at Login, gesture enablement, and the development override.
- [x] 6.4 Run `swift test --package-path /Users/arichyx/Documents/proj/lunchpad`, `git diff --check`, and targeted manual smoke tests for both languages, live ordering, shortcut conflict rollback/clear, launcher-Settings exclusivity, login-item UI, and gesture toggling.
- [x] 6.5 Run `VERSION=0.1.1-beta.1 ./Scripts/package-app.sh` and `VERSION=0.1.1-beta.1 ./Scripts/verify-package.sh`, then launch the packaged app and confirm localized resources resolve in both explicit languages.
