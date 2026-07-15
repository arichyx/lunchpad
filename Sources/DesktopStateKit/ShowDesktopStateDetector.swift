import AppKit
import CoreGraphics
import Foundation

public struct DesktopWindowSnapshot: Sendable, Equatable {
    public let ownerProcessIdentifier: pid_t
    public let layer: Int
    public let alpha: Double
    public let bounds: CGRect
    public let isRegularApplication: Bool

    public init(
        ownerProcessIdentifier: pid_t,
        layer: Int,
        alpha: Double,
        bounds: CGRect,
        isRegularApplication: Bool
    ) {
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
        self.isRegularApplication = isRegularApplication
    }
}

public struct ShowDesktopStateEvaluation: Sendable, Equatable {
    public let isActive: Bool
    public let visibleWindowCount: Int
    public let displacedWindowCount: Int
}

/// Infers the system Show Desktop state from WindowServer geometry.
///
/// macOS keeps displaced application windows in the on-screen window list while moving their
/// centres beyond the display edges. This reflects the actual system result regardless of whether
/// Show Desktop was entered by a trackpad gesture, Hot Corner, keyboard shortcut, or wallpaper.
public struct ShowDesktopStateDetector: Sendable {
    private let minimumWindowDimension: CGFloat
    private let displayEdgeTolerance: CGFloat

    public init(
        minimumWindowDimension: CGFloat = 100,
        displayEdgeTolerance: CGFloat = 50
    ) {
        self.minimumWindowDimension = minimumWindowDimension
        self.displayEdgeTolerance = displayEdgeTolerance
    }

    public func isActive() -> Bool {
        evaluate().isActive
    }

    public func evaluate() -> ShowDesktopStateEvaluation {
        let displays = Self.activeDisplayBounds()
        guard !displays.isEmpty else {
            return ShowDesktopStateEvaluation(
                isActive: false,
                visibleWindowCount: 0,
                displacedWindowCount: 0
            )
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(
            options,
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return ShowDesktopStateEvaluation(
                isActive: false,
                visibleWindowCount: 0,
                displacedWindowCount: 0
            )
        }

        let windows = entries.compactMap(Self.windowSnapshot)
        return evaluate(
            windows: windows,
            displayBounds: displays,
            ownProcessIdentifier: getpid()
        )
    }

    public func isActive(
        windows: [DesktopWindowSnapshot],
        displayBounds: [CGRect],
        ownProcessIdentifier: pid_t
    ) -> Bool {
        evaluate(
            windows: windows,
            displayBounds: displayBounds,
            ownProcessIdentifier: ownProcessIdentifier
        ).isActive
    }

    public func evaluate(
        windows: [DesktopWindowSnapshot],
        displayBounds: [CGRect],
        ownProcessIdentifier: pid_t
    ) -> ShowDesktopStateEvaluation {
        guard !displayBounds.isEmpty else {
            return ShowDesktopStateEvaluation(
                isActive: false,
                visibleWindowCount: 0,
                displacedWindowCount: 0
            )
        }

        let expandedDisplays = displayBounds.map {
            $0.insetBy(dx: -displayEdgeTolerance, dy: -displayEdgeTolerance)
        }
        var visibleWindowCount = 0
        var displacedWindowCount = 0

        for window in windows {
            guard window.ownerProcessIdentifier != ownProcessIdentifier,
                  window.isRegularApplication,
                  window.layer == 0,
                  window.alpha > 0.01,
                  window.bounds.width > minimumWindowDimension,
                  window.bounds.height > minimumWindowDimension else {
                continue
            }

            let centre = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
            if expandedDisplays.contains(where: { $0.contains(centre) }) {
                visibleWindowCount += 1
            } else {
                displacedWindowCount += 1
            }
        }

        // An empty desktop is not enough evidence: require at least one displaced app window.
        // WindowServer can leave a small number of sticky or transitional windows visible while
        // Show Desktop displaces the overwhelming majority of regular application windows.
        let isActive: Bool
        if visibleWindowCount == 0 {
            isActive = displacedWindowCount > 0
        } else {
            isActive = displacedWindowCount >= 3
                && displacedWindowCount >= visibleWindowCount * 3
        }
        return ShowDesktopStateEvaluation(
            isActive: isActive,
            visibleWindowCount: visibleWindowCount,
            displacedWindowCount: displacedWindowCount
        )
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return []
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(
            displayCount,
            &displays,
            &displayCount
        ) == .success else {
            return []
        }
        return displays.prefix(Int(displayCount)).map(CGDisplayBounds)
    }

    private static func windowSnapshot(
        from entry: [CFString: Any]
    ) -> DesktopWindowSnapshot? {
        guard let processIdentifier = entry[kCGWindowOwnerPID] as? NSNumber,
              let layer = entry[kCGWindowLayer] as? NSNumber,
              let alpha = entry[kCGWindowAlpha] as? NSNumber,
              let boundsValue = entry[kCGWindowBounds],
              let bounds = CGRect(
                  dictionaryRepresentation: boundsValue as! CFDictionary
              ) else {
            return nil
        }

        return DesktopWindowSnapshot(
            ownerProcessIdentifier: processIdentifier.int32Value,
            layer: layer.intValue,
            alpha: alpha.doubleValue,
            bounds: bounds,
            isRegularApplication: NSRunningApplication(
                processIdentifier: processIdentifier.int32Value
            )?.activationPolicy == .regular
        )
    }
}
