# Activation and Lifecycle Specification

## Purpose

Define how the resident accessory application starts, becomes visible, launches other apps, hides,
and terminates.
## Requirements
### Requirement: Quiet resident startup

Lunchpad SHALL start as an accessory application without automatically opening its full-screen launcher or creating a persistent Dock icon.

#### Scenario: Process launches

- **WHEN** Lunchpad finishes application initialization
- **THEN** it installs catalog monitoring, activation controls, and its menu bar item while leaving the launcher hidden

#### Scenario: Launcher window closes

- **WHEN** the reusable full-screen window is hidden
- **THEN** the Lunchpad process and its global monitors remain running

### Requirement: Menu bar controls

Lunchpad SHALL provide a menu bar status item for direct activation, settings access, and
termination.

#### Scenario: User left-clicks the status item

- **WHEN** the launcher is hidden and the status item receives a left mouse release
- **THEN** Lunchpad shows the launcher directly

#### Scenario: User right-clicks the status item

- **WHEN** the status item receives a right mouse release
- **THEN** Lunchpad presents a localized menu containing Show Lunchpad, Settings..., and Quit Lunchpad actions

#### Scenario: User chooses Settings

- **WHEN** the user invokes Settings... from the status-item or application menu
- **THEN** Lunchpad presents its reusable Settings window without terminating the resident process

### Requirement: Global hot key

Lunchpad SHALL register Control-Shift-Space by default, SHALL support any shortcut accepted by the
shortcut recorder, and SHALL support a disabled state through its preferences domain.

#### Scenario: Hot key is pressed while hidden

- **WHEN** the configured global hot key is pressed
- **THEN** Lunchpad activates and shows the launcher

#### Scenario: Hot key is pressed while visible

- **WHEN** the configured global hot key is pressed while the launcher is open
- **THEN** Lunchpad closes the launcher

#### Scenario: User selects an available shortcut

- **WHEN** Carbon successfully registers a candidate shortcut that differs from the active shortcut
- **THEN** Lunchpad makes the candidate active, unregisters the previous shortcut, and persists the candidate

#### Scenario: Candidate shortcut conflicts

- **WHEN** macOS reports that a candidate shortcut is already registered or cannot be registered
- **THEN** Lunchpad reports the conflict in Settings and preserves both the previously active shortcut and its stored preference

#### Scenario: User clears the shortcut

- **WHEN** the user clears the configured global shortcut
- **THEN** Lunchpad unregisters the active hot key, persists the disabled state, and leaves status-item and gesture activation available

#### Scenario: Development override is present

- **WHEN** `LUNCHPAD_HOTKEY` contains a recognized value
- **THEN** that value takes precedence over the stored `com.arichyx.Lunchpad` preference and Settings identifies the active shortcut as externally overridden

#### Scenario: Hot key registration fails during startup

- **WHEN** macOS rejects the requested stored or development-override shortcut during launch
- **THEN** Lunchpad continues running with its other activation methods and exposes the unavailable hot-key state in Settings

### Requirement: Optional launch at login

Lunchpad SHALL allow the user to register or unregister the packaged main application as a login item
through the public Service Management API, with the macOS registration state as the source of truth.

#### Scenario: User enables Launch at Login

- **WHEN** the user enables Launch at Login and macOS accepts the request
- **THEN** macOS registers Lunchpad to start as a quiet accessory application at login

#### Scenario: User disables Launch at Login

- **WHEN** the user disables Launch at Login and macOS accepts the request
- **THEN** macOS removes Lunchpad's main-app login registration

#### Scenario: Lunchpad is not running from an app bundle

- **WHEN** Settings is opened from a SwiftPM development executable that cannot be registered as a main-app login item
- **THEN** Lunchpad disables the Launch at Login control and explains that it is available in the packaged application

### Requirement: Immediate application launch dismissal

Lunchpad SHALL hide immediately after an application click and SHALL submit the application launch request asynchronously.

#### Scenario: Application takes several seconds to open

- **WHEN** the user clicks an application with a slow first launch
- **THEN** Lunchpad begins closing without waiting for Launch Services to finish opening the application

#### Scenario: Launch Services reports failure

- **WHEN** the asynchronous application launch request fails
- **THEN** Lunchpad reports the error without reopening or terminating the resident process

### Requirement: External application activation dismissal

Lunchpad SHALL close whenever another application becomes active while the launcher is visible.

#### Scenario: User activates an app from the Dock

- **WHEN** a Dock click activates a process other than Lunchpad
- **THEN** the visible launcher closes

#### Scenario: Lunchpad activates itself for presentation

- **WHEN** Lunchpad becomes active while showing its own launcher
- **THEN** it does not treat that activation as an external-app dismissal

### Requirement: Explicit termination

Lunchpad SHALL terminate only through an explicit quit action or normal process termination, not merely because its launcher window closes.

#### Scenario: User selects Quit Lunchpad

- **WHEN** the menu command or Command-Q invokes application termination
- **THEN** Lunchpad stops filesystem and multitouch monitoring and exits

### Requirement: Four-finger spread dismissal

Lunchpad SHALL close the visible launcher when a recognized four-finger outward spread completes,
using the same dismissal path and fixed-duration close animation as Escape, empty-space clicks, the
global hot key, application launch, and external application activation. The dismissal SHALL be
gated on the launcher being visible at completion and SHALL be available only while the Four-Finger
Pinch preference is enabled, because the spread shares the same `AppleMultitouchDevice` data stream
as the inward pinch. Hiding the launcher via this gesture SHALL NOT stop the resident process or its
global monitors.

#### Scenario: User spreads to dismiss while visible

- **WHEN** the launcher is visible and the user completes a recognized four-finger outward spread
- **THEN** Lunchpad closes the launcher with its fixed-duration close animation and the resident process keeps running

#### Scenario: Spread completes while hidden

- **WHEN** the launcher is hidden and a recognized four-finger outward spread completes
- **THEN** Lunchpad does not show or dismiss the launcher

#### Scenario: Spread dismissal unavailable when gesture preference is disabled

- **WHEN** Four-Finger Pinch is disabled in preferences and the user performs a four-finger outward spread while the launcher is visible
- **THEN** Lunchpad does not dismiss via the spread and the other dismissal methods remain available

