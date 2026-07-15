# Tahoe 26 Trackpad IOKit Data Path

This document records results verified on 2026-07-13 with macOS 26.5.1 and a built-in
Force Touch trackpad.

## Service topology

`com.apple.AppleMultitouchTrackpad` is the `ApplePreferenceIdentifier` of
`AppleMultitouchTrackpadHIDEventDriver`, not an IOService class that can be opened directly.
The actual raw-data entry point is its child node:

```text
AppleHIDTransportHIDDevice
└─ IOHIDInterface
   └─ AppleMultitouchTrackpadHIDEventDriver
      └─ AppleMultitouchDevice
         └─ AppleMultitouchDeviceUserClient
```

The probe therefore uses `IOServiceMatching("AppleMultitouchDevice")`.

## Open and read sequence

This sequence was derived from the `MultitouchSupport` implementation in the Tahoe dyld
shared cache and verified step by step with an independent probe:

1. Obtain `AppleMultitouchDevice` with `IOServiceGetMatchingService`.
2. Open its user client with `IOServiceOpen(service, mach_task_self_, 0, &connection)`.
3. Create a notification port with `IODataQueueAllocateNotificationPort()`.
4. Register the port with `IOConnectSetNotificationPort(connection, 0, port, 0)`.
5. Map the shared `IODataQueue` with `IOConnectMapMemory(connection, 0, ...)`.
6. Start the data stream with `IOConnectCallScalarMethod(connection, 0, [1], 1, ...)`.
7. Wait with `IODataQueueWaitForAvailableData`, then dequeue frames with
   `IODataQueueDequeue`.
8. On shutdown, pass `[0]` to the same selector to stop the stream, unmap the memory, and
   close the connection.

The tested hardware accepts both user-client type `0` and the four-character code `LFTR`.
The system implementation uses type `0`, so Lunchpad does the same.

## `0x75` report layout

The tested hardware reports type `0x75`, corresponding to V4 Precise Path + Image. The
following offsets were verified with real frames containing zero, one, and two contacts:

| Offset | Size | Meaning |
|---:|---:|---|
| 0 | 1 | Report type, `0x75` |
| 2 | 1 | Base header length; 32 on the tested hardware |
| 14 | 2 | Additional path header length, little-endian; 6 on the tested hardware |
| 16 | 2 | Total length of all contact records, little-endian |
| 22 | 1 | Number of contact records |

Contact records begin at `byte[2] + UInt16LE(byte[14...15])`. Each record has a stride of
`total contact length / contact count`, which is 30 bytes on the tested hardware:

| Contact offset | Size | Meaning |
|---:|---:|---|
| 0 | 1 | Contact identifier |
| 1 | 1 | Lifecycle state: 1/2 for down/move, 7 for up, and 0 for idle |
| 4 | 2 | Signed X relative to the sensor center, little-endian |
| 6 | 2 | Signed Y relative to the sensor center, little-endian |
| 12 | 2 | One contact-area axis length, not a coordinate |
| 14 | 2 | The other contact-area axis length, not a coordinate |

Do not hard-code the sensor dimensions. Prefer `Sensor Surface Width` and
`Sensor Surface Height` from IORegistry; they are 15600 and 9600 on the tested hardware.
`Max Packet Size` is 4096 on the same device.

## Pinch recognition

After parsing, states 0 and 7 are excluded. When at least four active fingers first appear,
the recognizer locks onto the first four identifiers. If the driver briefly reports a fifth
contact, it continues tracking the original four instead of resetting the gesture. Each frame
computes the mean of the six pairwise distances and records the maximum distance observed
during that four-finger contact sequence.

The recognizer fires once when the current distance contracts below 82% of the maximum, the
initial distance is sufficiently large, and no more than three seconds have elapsed. It unlocks
after the active contact count drops below four. A four-finger swipe preserves pairwise distances
closely enough that it does not satisfy the contraction threshold.

## Permissions and compatibility

- The current non-sandboxed SwiftPM app opens the user client directly without displaying an
  Input Monitoring permission prompt.
- For comparison, the public `IOHIDManagerOpen` path returns `kIOReturnNotPermitted` on the
  same machine and is subject to Input Monitoring/TCC. Lunchpad does not use that path.
- This uses public IOKit APIs against a private driver ABI, so compatibility across hardware and
  macOS releases is not guaranteed. The current parser accepts only `0x75` and safely ignores
  other report types.
- On Tahoe, `MultitouchSupport.framework` is dyld-cache-only. A missing on-disk Mach-O file does
  not prove that `dlopen` will fail. The original probe's segmentation fault also involved an
  incorrect dereference of a CFArray element pointer and omitted `MTDeviceStart`. Lunchpad still
  uses IOKit directly to avoid depending on private framework APIs.
