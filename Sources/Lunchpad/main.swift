import AppKit

// A command-line executable starts on the main thread; declare isolation explicitly for Swift 6.
MainActor.assumeIsolated {
    // Start NSApplication manually as an accessory-style launcher without a persistent Dock icon.
    let appDelegate = AppDelegate()
    let application = NSApplication.shared
    application.delegate = appDelegate
    application.setActivationPolicy(.accessory)

    application.activate(ignoringOtherApps: true)
    application.run()
}
