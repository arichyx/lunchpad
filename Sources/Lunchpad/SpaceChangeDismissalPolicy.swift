import Foundation

/// Pure decision for whether an active-Space notification should dismiss the launcher.
///
/// Extracted from `AppDelegate`'s `NSWorkspace.activeSpaceDidChangeNotification` handler so the
/// visibility gate and idempotence contract can be unit tested without driving AppKit or the full
/// resident lifecycle. The window's own `close()` path already guards against re-entry via its
/// `isVisible` and `isAnimatingClose` flags, so the policy only needs to express "should the
/// observer initiate a close".
enum SpaceChangeDismissalPolicy {
    enum Decision: Equatable {
        /// The launcher is on screen; start a dismissal through the normal close path.
        case dismiss
        /// The launcher is hidden (or already closing); the resident process stays as-is.
        case ignore
    }

    /// Returns the dismissal decision for a Space-change notification.
    ///
    /// - Parameters:
    ///   - isVisible: Whether the launcher is currently visible.
    ///   - isAnimatingClose: Whether a close transition is already in progress.
    static func decision(isVisible: Bool, isAnimatingClose: Bool) -> Decision {
        guard isVisible, !isAnimatingClose else { return .ignore }
        return .dismiss
    }
}
