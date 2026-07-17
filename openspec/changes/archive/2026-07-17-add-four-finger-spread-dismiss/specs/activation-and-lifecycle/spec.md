# activation-and-lifecycle delta — add-four-finger-spread-dismiss

## ADDED Requirements

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
