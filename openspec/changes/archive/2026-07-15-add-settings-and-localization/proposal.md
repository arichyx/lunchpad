## Why

Lunchpad currently has no in-app way to configure its resident behavior, and several user-facing
strings are hard-coded in a mixture of English and Chinese. A native settings experience is needed
so users can choose their language, catalog ordering, and activation controls without editing
preferences or environment variables.

## What Changes

- Add a reusable AppKit Settings window opened from a new **Settings...** command in the status-item
  menu, with standard single-window behavior and immediate application of supported preferences.
- Localize all Lunchpad-owned user-facing strings and accessibility text in English and Simplified
  Chinese, with **Follow System**, **English**, and **Chinese** language choices in the English UI.
- Add application ordering choices for name ascending, bundle creation time newest-first, and bundle
  modification time newest-first.
  Automatic ordering applies to applications within each logical container while preserving folder
  positions and persisted manual application positions.
- Replace the fixed hot-key preference parser with a native shortcut recorder that accepts a broad
  range of modified keys, detects Carbon global-registration conflicts, preserves the active shortcut
  when a replacement fails, and supports clearing the shortcut.
- Add **Launch at Login** and **Four-Finger Pinch** switches as focused resident-app preferences.
- Package and verify the localization resources in both development and release builds.

## Capabilities

### New Capabilities

- `settings-preferences`: AppKit settings-window presentation, preference persistence, language and
  ordering controls, shortcut recording, and additional resident-app settings.
- `user-interface-localization`: Runtime selection and complete English/Simplified Chinese coverage
  for Lunchpad-owned interface and accessibility strings.

### Modified Capabilities

- `activation-and-lifecycle`: Add the Settings menu command, runtime-safe configurable global hot
  keys, and optional launch-at-login registration.
- `logical-folders`: Define preference-controlled application ordering without destroying stored
  layout positions, and localize the protected Other folder using the selected interface language.
- `multitouch-gesture`: Allow users to disable or re-enable four-finger activation at runtime.
- `application-packaging`: Include and validate the SwiftPM localization resource bundle in packaged
  applications and release artifacts.

## Impact

- Affects `AppDelegate`, menu construction, main-menu construction, launcher refresh behavior,
  `GlobalHotKey`, application metadata, layout presentation, and multitouch monitor lifecycle.
- Introduces AppKit settings controllers/views, a typed preferences store, a localization service,
  shortcut-recording UI, ordering policy, and focused testable support types.
- Adds SwiftPM localization resources and corresponding app-bundle assembly and package-verification
  requirements; no account, telemetry, network service, or external package dependency is added.
