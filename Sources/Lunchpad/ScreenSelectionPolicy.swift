import AppKit

/// Selects the display that should host the launcher based on the global pointer location.
///
/// The policy is deterministic over the supplied screen geometry so multi-display arrangements
/// with negative origins or vertically stacked displays can be unit tested without depending on a
/// particular physical monitor layout. The first screen whose frame contains the pointer wins; if
/// no screen matches, the main screen index is used as a fallback.
///
/// Extracted from the pinch activation path so AppKit state (`NSEvent.mouseLocation`,
/// `NSScreen.screens`, `NSScreen.main`) is sampled once on the main actor and the containment
/// decision is independently testable.
enum ScreenSelectionPolicy {
    /// Returns the index of the screen that should host the launcher for the supplied pointer
    /// location.
    ///
    /// - When `pointerLocation` lies inside one of `screenFrames`, that screen's index is returned.
    /// - When the pointer is outside every reported screen, `mainScreenIndex` is returned as a
    ///   defensive fallback if it is present and within bounds.
    /// - When `screenFrames` is empty, or the pointer is unmatched and no valid main index is
    ///   available, the policy returns `nil` so the caller can keep its previously established
    ///   window frame or apply its own fallback.
    static func selectedIndex(
        pointerLocation: NSPoint,
        screenFrames: [NSRect],
        mainScreenIndex: Int?
    ) -> Int? {
        guard !screenFrames.isEmpty else { return nil }
        if let match = screenFrames.firstIndex(where: { $0.contains(pointerLocation) }) {
            return match
        }
        guard let mainScreenIndex, screenFrames.indices.contains(mainScreenIndex) else {
            return nil
        }
        return mainScreenIndex
    }

    /// Convenience wrapper that returns the selected `NSScreen` directly.
    ///
    /// `screens` is the live AppKit screen list. `mainScreen` is the screen AppKit currently
    /// reports as main, or `nil` if AppKit has no main screen during a display reconfiguration.
    static func selectedScreen(
        pointerLocation: NSPoint,
        screens: [NSScreen],
        mainScreen: NSScreen?
    ) -> NSScreen? {
        guard !screens.isEmpty else { return mainScreen }
        if let match = screens.first(where: { $0.frame.contains(pointerLocation) }) {
            return match
        }
        if let mainScreen, screens.contains(where: { $0 === mainScreen }) {
            return mainScreen
        }
        return screens.first
    }
}
