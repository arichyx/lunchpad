## Why

On a multi-display Mac, a four-finger pinch currently opens Lunchpad on `NSScreen.main` even when
the pointer and the user's attention are on another display. Lunchpad also remains visible across
Mission Control Space changes, leaving a stale full-screen overlay in a desktop context where the
user has intentionally navigated away.

## What Changes

- Resolve the display containing the current global mouse location when a four-finger pinch
  activates Lunchpad, and present all launcher windows on that display.
- Fall back safely to the main display if no connected screen contains the sampled pointer
  location.
- Observe active Space changes while the resident process is running and dismiss the launcher,
  using the existing close path, when a Space change occurs while it is visible.
- Keep other activation methods, quiet startup, resident monitoring, and Space changes while the
  launcher is hidden unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `launcher-interface`: Define pointer-display targeting for four-finger pinch presentation and
  consistent placement of the interaction, backdrop, and menu-bar-corner windows.
- `activation-and-lifecycle`: Require the visible launcher to close when the active macOS Space
  changes without terminating the resident application.

## Impact

- `Sources/Lunchpad/AppDelegate.swift`: pass a resolved target display from pinch activation and
  observe active Space changes.
- `Sources/Lunchpad/LunchpadWindow.swift`: accept an explicit presentation screen rather than
  always reading `NSScreen.main`.
- `Tests/LunchpadTests/`: cover screen selection and Space-change dismissal gating where the
  AppKit boundary can be isolated.
- No persistence schema, package dependency, network behavior, or packaging changes are expected.
