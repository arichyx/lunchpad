import AppKit

// A command-line executable starts on the main thread; declare isolation explicitly for Swift 6.
MainActor.assumeIsolated {
    // Start NSApplication manually as an accessory-style launcher without a persistent Dock icon.
    let appDelegate = AppDelegate()
    let application = NSApplication.shared
    application.delegate = appDelegate
    // Launching must not show the launcher or take focus from the frontmost app (for example
    // when started as a login item); presentation activates the app when it is needed.
    application.setActivationPolicy(.accessory)
    application.run()
}
