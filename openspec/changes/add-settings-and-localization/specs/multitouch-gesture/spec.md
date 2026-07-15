## MODIFIED Requirements

### Requirement: Direct trackpad data stream
When Four-Finger Pinch is enabled, Lunchpad SHALL attempt to read contact frames from
`AppleMultitouchDeviceUserClient` through IOKit without depending on `MultitouchSupport.framework`.
When the preference is disabled, Lunchpad SHALL NOT keep the driver data stream open.

#### Scenario: Compatible trackpad is present
- **WHEN** Four-Finger Pinch is enabled and the AppleMultitouchDevice service can be opened and its shared IODataQueue can be mapped
- **THEN** Lunchpad starts the data stream on a dedicated background queue

#### Scenario: Service cannot be opened
- **WHEN** Four-Finger Pinch is enabled but no compatible service exists or an IOKit operation fails
- **THEN** Lunchpad keeps running, records the gesture path as unavailable, and leaves menu bar and global-hot-key activation available

#### Scenario: Gesture activation is disabled
- **WHEN** Lunchpad starts or runs with Four-Finger Pinch disabled
- **THEN** it does not open or retain an AppleMultitouchDevice data stream and leaves the other activation methods available

#### Scenario: User disables an active monitor
- **WHEN** the user turns Four-Finger Pinch off while monitoring is active
- **THEN** Lunchpad stops the stream and clears any pending contact sequence without activating the launcher

#### Scenario: User re-enables gesture activation
- **WHEN** the user turns Four-Finger Pinch on after it was disabled
- **THEN** Lunchpad attempts to start a fresh monitor without requiring a process restart
