import AppKit

// A command-line executable starts on the main thread; declare isolation explicitly for Swift 6.
MainActor.assumeIsolated {
    // Start NSApplication manually as an accessory-style launcher without a persistent Dock icon.
    let appDelegate = AppDelegate()
    let application = NSApplication.shared
    application.delegate = appDelegate
    application.setActivationPolicy(.accessory)

    // Accessory apps do not receive an automatic application menu, so provide Command-Q.
    let mainMenu = NSMenu()
    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(
        withTitle: "退出 Lunchpad",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)
    application.mainMenu = mainMenu

    application.activate(ignoringOtherApps: true)
    application.run()
}
