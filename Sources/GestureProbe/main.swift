import AppKit

// Gesture probe v2 uses window-level monitoring to determine whether a four-finger pinch
// can be captured. The v1 global monitor could not receive gesture events because trackpad
// gestures are delivered only to the frontmost app window. This version installs a transparent
// window and observes events delivered to this process through a local monitor.
//
// Compare a two-finger pinch with the four-finger Apple Launchpad gesture.
// - If only the two-finger pinch produces .magnify, the four-finger gesture is reserved by
//   the system and does not produce a public NSEvent.
// - If both produce events, they can be distinguished by magnification or gesture sequence.

let mask: NSEvent.EventTypeMask = [
    .gesture, .magnify, .smartMagnify, .rotate,
    .beginGesture, .endGesture, .pressure, .scrollWheel,
    .mouseMoved, .leftMouseDown, .rightMouseDown
]

func log(_ tag: String, _ e: NSEvent) {
    print("[\(tag)] \(e.type) magn=\(String(format: "%.3f", e.magnification)) " +
          "stage=\(e.subtype.rawValue) phase=\(e.phase.rawValue)")
}

final class ProbeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: ProbeWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the global monitor to verify event delivery and permissions in another app.
        NSEvent.addGlobalMonitorForEvents(matching: mask) { e in log("GLOBAL", e) }
        // The local monitor is the primary diagnostic path for the transparent window.
        NSEvent.addLocalMonitorForEvents(matching: mask) { e in log("LOCAL", e); return e }

        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let win = ProbeWindow(contentRect: frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = NSColor.black.withAlphaComponent(0.001) // Nearly transparent, but still receives events.
        win.level = .floating
        win.acceptsMouseMovedEvents = true
        win.ignoresMouseEvents = false
        win.makeKeyAndOrderFront(nil)
        window = win

        print("=== GestureProbe v2 ===")
        print("透明窗口已铺满(会接住手势)。请依次做、每个之间停一下:")
        print("  1) 两指捏合缩放(像放大照片)")
        print("  2) 四指捏合(Lunchpad 手势)")
        print("  3) 双指双击")
        print("  4) 两指滚动")
        print("观察 [LOCAL] 打印。Ctrl+C 退出。")
        print("--------------------")
    }
}

let app = NSApplication.shared
let probeDelegate = ProbeDelegate()
app.delegate = probeDelegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
