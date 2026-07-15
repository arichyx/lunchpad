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

Lunchpad SHALL provide a menu bar status item for direct activation and termination.

#### Scenario: User left-clicks the status item

- **WHEN** the launcher is hidden and the status item receives a left mouse release
- **THEN** Lunchpad shows the launcher directly

#### Scenario: User right-clicks the status item

- **WHEN** the status item receives a right mouse release
- **THEN** Lunchpad presents a menu containing Show Lunchpad and Quit Lunchpad actions

### Requirement: Global hot key

Lunchpad SHALL register Control-Shift-Space by default and SHALL support Control-Option-L or a disabled state through its preferences domain.

#### Scenario: Hot key is pressed while hidden

- **WHEN** the configured global hot key is pressed
- **THEN** Lunchpad activates and shows the launcher

#### Scenario: Hot key is pressed while visible

- **WHEN** the configured global hot key is pressed while the launcher is open
- **THEN** Lunchpad closes the launcher

#### Scenario: Development override is present

- **WHEN** `LUNCHPAD_HOTKEY` contains a recognized value
- **THEN** that value takes precedence over the stored `com.arichyx.Lunchpad` preference

#### Scenario: Hot key registration fails

- **WHEN** macOS rejects the requested key combination
- **THEN** Lunchpad continues running with its other activation methods available

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
