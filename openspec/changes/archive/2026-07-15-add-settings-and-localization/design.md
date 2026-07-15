## Context

Lunchpad is currently a single AppKit executable target. `AppDelegate` owns the status item,
launcher window, Carbon global hot key, catalog synchronizer, and multitouch monitor. The status
menu is hard-coded, the application menu contains a Chinese Quit command, the global shortcut is
loaded from one of two string aliases, and the Other folder chooses its name directly from
`Locale.preferredLanguages`.

The layout database already stores stable app and folder positions. Catalog reconciliation returns
that canonical order, while `AppScanner` reads file modification metadata for stability checks and
can attach bundle creation and modification dates to `AppItem` for presentation ordering. The
implementation must preserve the AppKit-only,
SwiftPM-only accessory model, keep all settings local, and ensure resource localization also works
inside the assembled `.app`, ZIP, and DMG.

## Goals / Non-Goals

**Goals:**

- Provide one native, reusable Settings window with immediately applied, durable preferences.
- Localize every Lunchpad-owned interface and accessibility string in English and Simplified
  Chinese, including runtime language switching.
- Offer deterministic name and modification-time app ordering without mutating logical layout data.
- Make arbitrary supported Carbon shortcuts safely replaceable, conflict-aware, and clearable.
- Add reliable login-item and gesture-monitor controls with honest error state.
- Keep preference parsing, language resolution, shortcut validation, and ordering logic testable.

**Non-Goals:**

- Localizing third-party application display names independently of macOS language preferences.
- Adding Traditional Chinese, downloadable language packs, accounts, sync, telemetry, or networking.
- Adding manual drag reordering, folder editing, destructive layout reset, or an Xcode project.
- Enumerating every shortcut owned by other processes; macOS exposes no complete public registry.
- Replacing the existing Carbon hot-key or private multitouch driver paths.

## Decisions

### 1. Use a typed preference model and one main-actor coordinator

Introduce typed values for interface language (`system`, `en`, `zh-Hans`), app ordering (`name`,
`creationDate`, `modificationDate`), gesture intent, and a versioned shortcut payload containing the
hardware key code and Carbon modifiers. Store them in
`UserDefaults(suiteName: "com.arichyx.Lunchpad")` behind a
small preferences store that validates each key independently and publishes main-actor changes.

`AppDelegate` remains the runtime coordinator. It owns the current raw catalog and responds to a
preference change by refreshing only the affected subsystem: rebuild localized menus and visible
strings, reapply ordering to cached items, swap the hot key, or start/stop gesture monitoring.
Launch at Login is not mirrored into UserDefaults because `SMAppService.mainApp.status` is the
authoritative state.

The existing string-form `globalHotKey` preference is migrated on read for the two recognized
shortcuts and disabled aliases. A malformed value falls back to Control-Shift-Space without
affecting other settings.

Alternative considered: read `UserDefaults` ad hoc from each controller. This would duplicate
fallback and migration behavior and make atomic hot-key replacement and runtime UI refresh harder
to reason about.

### 2. Build a programmatic single-pane AppKit Settings window

Add a retained `NSWindowController` with one compact General pane built from AppKit controls. Group
Language and Application Order under Appearance, and Shortcut, Launch at Login, and Four-Finger
Pinch under Activation. A custom `NSView`-based shortcut recorder becomes first responder while
recording and converts `keyDown` events into normalized key-code/modifier values.

The right-click status menu gains Settings... between Show Lunchpad and the separator before Quit.
The accessory application's main menu also gains the standard Command-Comma Settings command once
the settings window is available. Opening Settings closes the full-screen launcher; showing the
launcher orders out Settings so the two interaction models do not overlap. Repeated Settings
commands reuse and focus the same window. The retained window uses AppKit's `moveToActiveSpace`
collection behavior so invoking Settings from another Space moves the window to the user's current
Space instead of navigating back to the Space where the window first appeared.

Alternative considered: SwiftUI `Settings` scenes. This is rejected because the repository requires
AppKit unless a separate architectural decision approves SwiftUI, and a programmatic form is small
enough to keep native behavior without another UI framework.

### 3. Resolve localization through explicit resource bundles

Add `en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings` as processed resources for
the Lunchpad executable target. An injected `AppLocalizer` resolves an explicit language bundle and
returns English as the fallback for a missing selected-language key. Follow System maps any
preferred Chinese locale to Simplified Chinese and otherwise selects English.

Do not rely on process-global `AppleLanguages` mutation or `NSLocalizedString` caching because both
are poorly suited to live language changes. Controllers ask the localizer for stable keys and expose
a `refreshLocalizedContent()` path. On language change, `AppDelegate` rebuilds the status and main
menus, refreshes Settings and launcher strings, asks the layout presentation layer to rename the
protected Other folder, and reapplies name ordering with the resolved collation locale.

Application names remain sourced from each application bundle using macOS preferred localizations.
The selected Lunchpad language only affects Lunchpad-owned strings.

The package script locates the SwiftPM-generated resource bundle beside the built executable and
copies it into `Contents/Resources` before signing. The localization service resolves that standard
packaged location first and falls back to `Bundle.module` for direct SwiftPM development runs.
Verification asserts that the processed English and Simplified Chinese tables exist in the app and
in the mounted DMG copy.

Alternative considered: embed translation dictionaries in Swift source. Resource tables provide
standard tooling, clean fallback behavior, and packaging checks without mixing translations into
controller code.

### 4. Treat app ordering as a non-destructive presentation policy

Extend discovered `AppItem` metadata with the application bundle's filesystem creation and
modification dates. Avoid a SQLite migration: after layout reconciliation, enrich returned apps
from the current discovery map by stable identity. Include both dates in the catalog signature so
bundle replacements and updates can trigger a reordered refresh.

`ApplicationOrderingPolicy` sorts folder members directly. At the root it extracts root apps, sorts
them, then reinserts them into the existing app slots so logical folders keep their canonical
positions. Name ordering uses localized, case-insensitive numeric comparison for the resolved
interface locale and stable identity as a final tie-breaker. Creation and modification ordering are
both newest-first, place unknown dates last, then use the same name and identity tie-breakers.

`AppDelegate` retains the most recent canonical catalog and applies the policy before sending items
to `LunchpadWindow`. Changing the preference or language reorders that cached value immediately and
never calls the scanner or changes SQLite `sort_position` values.

Alternative considered: rewrite SQLite positions whenever the mode changes. This would destroy the
canonical layout and make switching modes irreversible, so it is explicitly avoided.

### 5. Use actual Carbon registration as the conflict check

Represent a shortcut by hardware key code and Carbon modifier bits; derive its display glyphs at
runtime rather than persisting localized text. The recorder accepts function keys alone or ordinary
keys combined with Command, Control, or Option; Shift can supplement but cannot make an ordinary key
safe by itself. Escape cancels recording, while the visible clear button (and Delete while focused)
disables the shortcut.

For a changed candidate, construct/register a new `GlobalHotKey` with a unique event ID while the
old object remains alive. If registration succeeds, persist the candidate, swap references, and
release the old registration. If Carbon returns `eventHotKeyExistsErr` or another error, destroy the
candidate, keep the old registration and preference, and show localized feedback. Selecting the
already-active shortcut is a no-op. Clearing releases the old object before persisting disabled.

Retain `LUNCHPAD_HOTKEY` as a development override. When present, Settings displays the override and
disables shortcut editing so stored state cannot be mistaken for active state.

Alternative considered: unregister the old shortcut before testing the new one. A failed candidate
would leave users without the prior activation path and would make rollback racy.

### 6. Use system state for Login at Launch and explicit intent for gestures

Wrap `SMAppService.mainApp` behind a small service. Settings reads `status`, calls `register()` or
`unregister()`, then rereads status. On error it restores the switch to system state and shows the
localized error. A raw SwiftPM executable is not a registerable main app, so the control is disabled
with an explanation outside a packaged `.app`.

Four-Finger Pinch remains enabled by default. Disabling it stores user intent, stops and releases the
monitor, and clears pending recognition. Enabling it creates a fresh monitor and attempts to start
the existing IOKit path. A start failure does not flip the saved intent back off; Settings reports
that the enabled feature is currently unavailable so future launches can retry automatically.

Alternative considered: store a second Launch at Login Boolean. Duplicating macOS registration
state would drift when the user changes Login Items in System Settings.

### 7. Test pure policies and perform focused integration verification

Keep language resolution, preference decoding/migration, shortcut validation, ordering, and error
mapping free of UI dependencies where practical, extracting a small internal support target only if
needed to import them from tests. Add focused tests for defaults and malformed data, all sort modes
and tie-breakers, folder-slot preservation, language resolution/fallback, legacy shortcut migration,
and candidate-swap rollback through a fake registrar.

Integration verification covers status/menu actions, single-window behavior, live localization,
shortcut recording and clearing, login-item error rollback, gesture monitor lifecycle, and packaged
resource discovery. No test shall mutate the user's real login-item registration or global hot keys;
those boundaries use injected adapters plus a manual smoke test in the built app.

## Risks / Trade-offs

- [Risk] Carbon reports conflicts for registrations it owns but macOS provides no complete public
  API for enumerating every application or system shortcut. → Use real candidate registration as the
  authoritative check, explain unregistrable errors accurately, and document that a successfully
  registered shortcut can still overlap higher-level application behavior.
- [Risk] Bundle directory creation dates are filesystem metadata and can be preserved from a source
  package, so they do not reliably mean installation or release time. → Label the setting Creation
  Time, sort the available bundle creation timestamp only, and document newest-first semantics.
- [Risk] Bundle modification dates can change for metadata-only updates and do not mean "last
  used." → Label the setting Modification Time and sort the bundle timestamp only.
- [Risk] Runtime localization can leave stale strings in retained views. → Centralize refresh entry
  points and add a manual checklist that exercises menus, launcher root/folder/search states,
  Settings, accessibility labels, and errors in both languages.
- [Risk] SwiftPM resource-bundle placement differs from a conventional Xcode app. → Discover the
  built resource bundle from SwiftPM's bin path, fail packaging when absent, and verify locale tables
  after signing and inside the mounted DMG.
- [Risk] `SMAppService.mainApp` behavior is meaningful only for a packaged application and can be
  denied by user/system policy. → Disable it for development executables, use system status as truth,
  and surface errors without claiming registration succeeded.
- [Trade-off] Re-inserting sorted apps into existing root app slots preserves folder placement but
  can produce app groups separated by folders. This is intentional to protect logical layout.

## Migration Plan

1. Add preference/localization infrastructure with defaults matching current startup behavior where
   possible, and migrate recognized legacy hot-key strings on read.
2. Add application metadata enrichment and non-destructive ordering before wiring Settings controls.
3. Add the Settings window and connect runtime updates to menus, launcher, hot key, gesture monitor,
   and login-item service.
4. Add processed localization resources, update packaging and verification, then test both direct
   SwiftPM execution and the assembled application.
5. Rollback can remove the new settings UI and readers while leaving unknown UserDefaults keys
   harmless; no SQLite schema or user layout data requires reversal.

## Open Questions

No blocking decisions remain. Additional languages, sort directions, manual ordering, and layout
reset are intentionally deferred to future changes.
