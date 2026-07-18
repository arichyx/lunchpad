## 1. Pointer-Screen Presentation

- [x] 1.1 Add a deterministic screen-frame selection policy with main-screen fallback, and unit
  tests for main, non-main, negative-origin, vertically stacked, and unmatched pointer locations.
- [x] 1.2 Change `LunchpadWindow.show` to accept an explicit target screen and derive every
  launcher-owned window frame, Dock exclusion, safe-area inset, and grid height from that screen.
- [x] 1.3 Resolve the screen containing `NSEvent.mouseLocation` on the main actor for completed
  four-finger pinch activation, while preserving existing main-screen behavior for status-item and
  hot-key activation.

## 2. Active Space Dismissal

- [x] 2.1 Register a main-queue `NSWorkspace.activeSpaceDidChangeNotification` observer during app
  startup and remove it during application termination.
- [x] 2.2 Route active Space changes through the existing close path only when the launcher is
  visible, preserve idempotence during a concurrent dismissal, and add focused lifecycle tests for
  visible and hidden states.

## 3. Validation

- [x] 3.1 Run `swift test --package-path /Users/arichyx/proj/arichyx/personal/lunchpad` and resolve
  any regressions.
- [x] 3.2 Manually verify that a pinch opens on the pointer's display in a two-display arrangement,
  that all launcher-owned windows stay together, and that switching Spaces closes the launcher.
- [x] 3.3 Run `git diff --check` and confirm no packaging, persistence, or generated artifacts were
  changed.
