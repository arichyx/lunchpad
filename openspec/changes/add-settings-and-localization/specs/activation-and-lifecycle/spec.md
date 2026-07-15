## MODIFIED Requirements

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

## ADDED Requirements

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
