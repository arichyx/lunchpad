## ADDED Requirements

### Requirement: Pointer-screen presentation for four-finger pinch

Lunchpad SHALL sample the global pointer location when a recognized four-finger inward pinch
activates the hidden launcher and SHALL present the complete launcher on the connected screen
containing that point. The interaction window, backdrop, menu-bar coverage, Dock exclusion, safe
area layout, and grid layout SHALL all use the same selected screen for that presentation. If no
connected screen contains the sampled point, Lunchpad SHALL fall back to the main screen.

#### Scenario: Pointer is on a non-main display when pinch completes

- **WHEN** the launcher is hidden, the pointer is within a connected non-main display, and a
  recognized four-finger inward pinch completes
- **THEN** Lunchpad presents its interaction and supporting windows on that non-main display

#### Scenario: Pointer is on the main display when pinch completes

- **WHEN** the launcher is hidden, the pointer is within the main display, and a recognized
  four-finger inward pinch completes
- **THEN** Lunchpad presents the complete launcher on the main display

#### Scenario: Pointer does not match a connected screen

- **WHEN** a recognized four-finger inward pinch activates Lunchpad while the sampled global
  pointer location is outside every currently reported screen frame
- **THEN** Lunchpad presents on the main screen without terminating or showing launcher-owned
  windows on different screens

#### Scenario: Pointer moves after presentation begins

- **WHEN** pinch activation selects a screen and the pointer subsequently moves to another display
  during the opening animation
- **THEN** all launcher-owned windows remain on the originally selected screen for that
  presentation
