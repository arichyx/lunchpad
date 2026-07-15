## ADDED Requirements

### Requirement: Native settings presentation
Lunchpad SHALL provide a programmatic AppKit Settings window without changing its accessory
activation policy or creating a persistent Dock icon.

#### Scenario: User opens Settings
- **WHEN** the user chooses Settings... from the status-item menu
- **THEN** Lunchpad closes the full-screen launcher if necessary, activates itself, and presents a titled Settings window

#### Scenario: Settings is already open
- **WHEN** the user invokes Settings... again
- **THEN** Lunchpad brings the existing Settings window to the front instead of creating another window

#### Scenario: Settings is invoked from another Space
- **WHEN** the retained Settings window was previously shown on a different macOS Space
- **THEN** Lunchpad moves it to the currently active Space instead of switching back to its previous Space

#### Scenario: User closes Settings
- **WHEN** the user closes the Settings window
- **THEN** the resident Lunchpad process, status item, catalog monitor, and enabled activation controls continue running

### Requirement: Durable typed preferences
Lunchpad SHALL persist interface language, application ordering, global shortcut, and four-finger
activation intent as typed values in the `com.arichyx.Lunchpad` preferences domain.

#### Scenario: User changes a preference
- **WHEN** a supported preference is changed successfully
- **THEN** Lunchpad applies it during the current process and restores it after the next launch

#### Scenario: No stored preference exists
- **WHEN** Lunchpad loads a setting for the first time
- **THEN** it uses Follow System language, name ordering, Control-Shift-Space, disabled Launch at Login, and enabled Four-Finger Pinch defaults

#### Scenario: Stored preference data is invalid
- **WHEN** a preference has an unknown enum value or malformed shortcut payload
- **THEN** Lunchpad falls back to that setting's default without terminating or discarding unrelated valid settings

### Requirement: Application ordering control
Lunchpad SHALL offer Name, Creation Time, and Modification Time ordering for applications in the
root and in every logical folder. Root-level logical folders SHALL retain their persisted positions
while root apps are reordered among the existing app slots.

#### Scenario: Name ordering is selected
- **WHEN** the application catalog is displayed with Name selected
- **THEN** apps in each logical container are ordered by localized case-insensitive name ascending, with stable identity as the final tie-breaker

#### Scenario: Creation Time ordering is selected
- **WHEN** the application catalog is displayed with Creation Time selected
- **THEN** apps in each logical container are ordered by application-bundle filesystem creation time newest-first, with missing dates last and name then stable identity as tie-breakers

#### Scenario: Modification Time ordering is selected
- **WHEN** the application catalog is displayed with Modification Time selected
- **THEN** apps in each logical container are ordered by application-bundle modification time newest-first, with missing dates last and name then stable identity as tie-breakers

#### Scenario: Ordering changes while the launcher is visible
- **WHEN** the user selects another application ordering in Settings
- **THEN** the visible launcher refreshes from its cached catalog without performing a filesystem rescan or resetting folder and page validity

#### Scenario: User switches ordering modes
- **WHEN** Lunchpad applies any automatic ordering mode
- **THEN** it does not rewrite persisted application assignments or sort positions in the layout database

### Requirement: Shortcut recording control
Lunchpad SHALL provide a keyboard-first shortcut recorder with an explicit clear action and localized
validation feedback.

#### Scenario: User records a modified key
- **WHEN** the recorder receives a key with Command, Control, or Option, optionally combined with Shift
- **THEN** it presents the normalized macOS shortcut glyphs and asks the activation system to apply the candidate

#### Scenario: User records a function key
- **WHEN** the recorder receives a supported function key without another modifier
- **THEN** it treats the function key as a valid candidate shortcut

#### Scenario: User enters an unsafe shortcut
- **WHEN** the recorder receives only modifier keys, a normal unmodified typing key, or an unsupported key
- **THEN** it rejects the candidate and keeps the previously active shortcut

#### Scenario: User clears the shortcut
- **WHEN** the user invokes the recorder's clear action
- **THEN** the recorder displays no shortcut and Lunchpad disables global-hot-key activation

### Requirement: Focused resident behavior controls
Lunchpad SHALL expose Launch at Login and Four-Finger Pinch switches and SHALL show failures without
silently presenting a state that was not applied.

#### Scenario: Login registration fails
- **WHEN** macOS rejects a Launch at Login registration or unregistration request
- **THEN** Settings restores the switch to the system-reported state and displays a localized error

#### Scenario: Gesture monitoring is unavailable
- **WHEN** Four-Finger Pinch is enabled but the trackpad monitor cannot start
- **THEN** Settings preserves the enabled intent and displays that gesture activation is currently unavailable
