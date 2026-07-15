# Multitouch Gesture Specification

## Purpose

Define the four-finger inward-pinch activation path, its recognition semantics, and its safe
fallback behavior on unsupported trackpads or driver changes.

## Requirements

### Requirement: Direct trackpad data stream

Lunchpad SHALL attempt to read contact frames from `AppleMultitouchDeviceUserClient` through IOKit without depending on `MultitouchSupport.framework`.

#### Scenario: Compatible trackpad is present

- **WHEN** the AppleMultitouchDevice service can be opened and its shared IODataQueue can be mapped
- **THEN** Lunchpad starts the data stream on a dedicated background queue

#### Scenario: Service cannot be opened

- **WHEN** no compatible service exists or an IOKit operation fails
- **THEN** Lunchpad keeps running and leaves menu bar and global-hot-key activation available

### Requirement: Bounded report parsing

Lunchpad SHALL parse only supported `0x75` precise-path reports and SHALL reject malformed or unsupported packets without reading beyond their declared bounds.

#### Scenario: Valid precise-path frame arrives

- **WHEN** a `0x75` packet has consistent header, contact count, and contact-record lengths
- **THEN** Lunchpad emits contacts normalized against the trackpad's reported sensor dimensions

#### Scenario: Unsupported report arrives

- **WHEN** a packet has another report type or inconsistent lengths
- **THEN** Lunchpad ignores the packet without terminating the read loop

### Requirement: Four-finger inward-pinch recognition

Lunchpad SHALL recognize an inward pinch from the contraction of mean pairwise distance among four tracked active contacts.

#### Scenario: Four contacts contract sufficiently

- **WHEN** four tracked contacts begin sufficiently spread apart and contract to 82 percent or less of their observed maximum distance within three seconds
- **THEN** Lunchpad marks one pinch activation as pending

#### Scenario: Four contacts move together without contracting

- **WHEN** a four-finger swipe preserves the contacts' pairwise distances
- **THEN** Lunchpad does not recognize it as an inward pinch

#### Scenario: Driver briefly reports a fifth contact

- **WHEN** a fifth active contact appears while the original four remain present
- **THEN** Lunchpad continues tracking the original four without resetting the gesture

#### Scenario: Gesture remains stationary too long

- **WHEN** the active four-finger sequence exceeds three seconds without triggering
- **THEN** Lunchpad resets the distance baseline to prevent a delayed activation

### Requirement: Activation after contact release

Lunchpad SHALL defer launcher presentation until a recognized pinch has completed and the user has lifted the gesture contacts.

#### Scenario: Threshold is reached while fingers remain down

- **WHEN** contraction crosses the recognition threshold but at least two active contacts remain
- **THEN** Lunchpad keeps the activation pending and does not show the launcher yet

#### Scenario: User releases the recognized gesture

- **WHEN** the active contact count drops below two after a recognized pinch
- **THEN** Lunchpad emits exactly one activation and rearms only after the contact sequence resets

### Requirement: Hardware compatibility boundary

Lunchpad SHALL fail safely when a trackpad or macOS release does not provide the verified report format.

#### Scenario: External trackpad uses a different report format

- **WHEN** contact packets do not match the supported `0x75` layout
- **THEN** four-finger activation remains unavailable while all non-gesture launcher features continue operating
