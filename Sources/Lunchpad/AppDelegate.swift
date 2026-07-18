import AppKit
import DesktopStateKit
import MultitouchKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = LunchpadPreferences()
    private lazy var localizer = AppLocalizer(language: preferences.interfaceLanguage)
    private var window: LunchpadWindow?
    private var canonicalItems: [LunchpadItem] = []
    private var catalogSynchronizer: ApplicationCatalogSynchronizer?
    private var hotKeyController: HotKeyController?
    private let loginItemController = LoginItemController()
    private var gestureMonitorController: GestureMonitorController?
    private var settingsWindowController: SettingsWindowController?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var activeSpaceChangeObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var debugLastContactCount = -1
    private var debugMaximumDistance: Double?
    private var debugLastPrintAt = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences.onChange = { [weak self] change in
            self?.applyPreferenceChange(change)
        }
        let scanner = AppScanner()
        let store: LunchpadLayoutStore?
        do {
            let openedStore = try LunchpadLayoutStore()
            store = openedStore
            print("布局数据库：\(openedStore.databaseURL.path)")
        } catch {
            print("⚠️ 布局数据库不可用，使用平铺布局：\(error)")
            store = nil
        }

        let synchronizer = ApplicationCatalogSynchronizer(
            scanner: scanner,
            layoutStore: store
        )
        synchronizer.onCatalogRefresh = {
            [weak self] items, catalogChanged, invalidatedIconPaths in
            self?.applyCatalogRefresh(
                items,
                catalogChanged: catalogChanged,
                invalidatedIconPaths: invalidatedIconPaths
            )
        }
        do {
            // Start monitoring before the initial scan to cover changes that race with startup.
            try synchronizer.start()
            print("应用目录监听已启动")
        } catch {
            print("⚠️ 应用目录监听启动失败：\(error)")
        }
        catalogSynchronizer = synchronizer

        // Restore logical folders from SQLite after scanning; Finder directories are not folders.
        let items = synchronizer.loadInitialCatalog()
        canonicalItems = items
        let appCount = items.reduce(0) { $0 + $1.apps.count }
        let folderCount = items.reduce(0) { count, item in
            if case .folder = item { return count + 1 }
            return count
        }
        print("扫描完成：\(appCount) 个应用，\(folderCount) 个文件夹")
        window = LunchpadWindow(
            items: presentedItems(from: items),
            localizer: localizer,
            rootPageStore: RootPageStore()
        )

        installStatusItem()
        installApplicationMenu()
        installGlobalHotKey()
        installMultitouchMonitor()
        installWorkspaceActivationObserver()
        installActiveSpaceChangeObserver()
    }

    func applicationWillTerminate(_ notification: Notification) {
        catalogSynchronizer?.stop()
        gestureMonitorController?.stop()
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        if let activeSpaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceChangeObserver)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installGlobalHotKey() {
        let controller = HotKeyController { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleLunchpad()
            }
        }
        controller.start(storedPreference: preferences.hotKey)
        hotKeyController = controller

        guard let configuration = controller.activeConfiguration else {
            if let error = controller.lastError {
                print("⚠️ Global hot key registration failed: \(error)")
            } else {
                print("Global hot key disabled")
            }
            return
        }

        if controller.isExternallyManaged {
            print("Global hot key registered from LUNCHPAD_HOTKEY: \(configuration.displayName)")
        } else {
            print("Global hot key registered: \(configuration.displayName)")
        }
    }

    private func installStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }
        if let button = statusItem?.button {
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let image = NSImage(
                systemSymbolName: "square.grid.3x3.fill",
                accessibilityDescription: localizer.string("status.accessibility")
            )?.withSymbolConfiguration(configuration)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "Lunchpad"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        let showItem = NSMenuItem(
            title: localizer.string("menu.show"),
            action: #selector(showLunchpadFromStatusItem(_:)),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let settingsItem = NSMenuItem(
            title: localizer.string("menu.settings"),
            action: #selector(showSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: localizer.string("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusMenu = menu
    }

    private func installApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: localizer.string("menu.settings"),
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: localizer.string("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            guard let statusItem, let statusMenu else { return }
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            showLunchpad()
        }
    }

    @objc private func showLunchpadFromStatusItem(_ sender: Any?) {
        showLunchpad()
    }

    @objc private func showSettings(_ sender: Any?) {
        window?.close()
        guard let hotKeyController else { return }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                preferences: preferences,
                localizer: localizer,
                hotKeyController: hotKeyController,
                loginItemController: loginItemController,
                gestureErrorProvider: { [weak self] in
                    self?.gestureMonitorController?.lastErrorDescription
                }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.show()
    }

    private func installWorkspaceActivationObserver() {
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activatedProcessIdentifier = (
                notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            )?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let window = self.window, window.isVisible else { return }
                guard let activatedProcessIdentifier,
                      activatedProcessIdentifier
                        != ProcessInfo.processInfo.processIdentifier else {
                    return
                }
                window.close()
            }
        }
    }

    /// Registers a main-queue observer for `NSWorkspace.activeSpaceDidChangeNotification`.
    ///
    /// When macOS reports an active Space change while the launcher is visible, Lunchpad dismisses
    /// through the normal close path. The resident process, monitors, and settings window are
    /// left running. Hidden state, in-progress close animations, and unrelated notifications are
    /// ignored. The existing `LunchpadWindow.close` guard keeps the close idempotent if a Space
    /// change races another dismissal.
    private func installActiveSpaceChangeObserver() {
        activeSpaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                let decision = SpaceChangeDismissalPolicy.decision(
                    isVisible: window.isVisible,
                    isAnimatingClose: window.isAnimatingClose
                )
                guard decision == .dismiss else { return }
                window.close()
            }
        }
    }

    private func installMultitouchMonitor() {
        let controller = GestureMonitorController { [weak self] monitor in
            self?.configureMultitouchMonitor(monitor)
        }
        gestureMonitorController = controller
        controller.setEnabled(preferences.fourFingerPinchEnabled)
        if let error = controller.lastErrorDescription {
            print("⚠️ Four-finger pinch monitor failed to start: \(error)")
        } else if controller.isMonitoring {
            print("Four-finger pinch monitor started")
        }
    }

    private func configureMultitouchMonitor(_ monitor: any GestureMonitoring) {
        let showDesktopStateDetector = ShowDesktopStateDetector()
        let gestureDebugEnabled = ProcessInfo.processInfo.environment[
            "LUNCHPAD_GESTURE_DEBUG"
        ] == "1"
        monitor.shouldActivatePinch = {
            let evaluation = showDesktopStateDetector.evaluate()
            if gestureDebugEnabled {
                print(
                    "[Gesture] showDesktop=\(evaluation.isActive) "
                        + "visible=\(evaluation.visibleWindowCount) "
                        + "displaced=\(evaluation.displacedWindowCount)"
                )
            }
            return !evaluation.isActive
        }
        monitor.onPinch = { [weak self] in
            print("Four-finger pinch completed; showing Lunchpad")
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Resolve the pointer's display on the main actor so AppKit APIs are reached
                // safely and the screen list cannot change between sampling and presentation.
                self.showLunchpad(targetScreen: self.screenForPinchActivation())
            }
        }
        monitor.onExpand = { [weak self] in
            print("Four-finger spread completed; hiding Lunchpad")
            Task { @MainActor [weak self] in
                self?.dismissLunchpad()
            }
        }
        monitor.onPinchSuppressed = {
            print("Show Desktop is active; leaving this pinch to macOS")
        }
        if gestureDebugEnabled {
            monitor.onFrame = { [weak self] frame in
                Task { @MainActor [weak self] in
                    self?.printGestureDebugFrame(frame)
                }
            }
        }
        monitor.onError = { [weak self] error in
            print("⚠️ Trackpad data stream stopped: \(error)")
            Task { @MainActor [weak self] in
                self?.gestureMonitorController?.reportRuntimeError(error)
                self?.settingsWindowController?.refreshLocalizedContent()
            }
        }
    }

    private func showLunchpad() {
        showLunchpad(targetScreen: nil)
    }

    private func showLunchpad(targetScreen: NSScreen?) {
        guard let window, !window.isVisible else { return }
        settingsWindowController?.window?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.show(on: targetScreen)
    }

    /// Resolves the screen that should host the launcher when a four-finger pinch activates it.
    ///
    /// Samples `NSEvent.mouseLocation` on the main actor (the multitouch callback is off-thread)
    /// and selects the connected display whose frame contains that point. Falls back to
    /// `NSScreen.main`, then to `nil` (which lets `LunchpadWindow.show` keep its previous
    /// main-screen behavior) when no screen contains the pointer.
    private func screenForPinchActivation() -> NSScreen? {
        let pointerLocation = NSEvent.mouseLocation
        return ScreenSelectionPolicy.selectedScreen(
            pointerLocation: pointerLocation,
            screens: NSScreen.screens,
            mainScreen: NSScreen.main
        )
    }

    private func dismissLunchpad() {
        guard let window, window.isVisible else { return }
        window.close()
    }

    private func applyCatalogRefresh(
        _ items: [LunchpadItem],
        catalogChanged: Bool,
        invalidatedIconPaths: Set<String>?
    ) {
        canonicalItems = items
        let appCount = items.reduce(0) { $0 + $1.apps.count }
        let reason = catalogChanged ? "目录变化" : "应用内容变化"
        print("应用目录已同步（\(reason)）：\(appCount) 个应用")
        window?.update(
            items: presentedItems(from: items),
            catalogChanged: catalogChanged,
            invalidatedIconPaths: invalidatedIconPaths
        )
    }

    private func applyPreferenceChange(_ change: LunchpadPreferenceChange) {
        switch change {
        case .interfaceLanguage:
            localizer.setLanguage(preferences.interfaceLanguage)
            refreshPresentedCatalog(animated: false)
            rebuildStatusMenu()
            installApplicationMenu()
            window?.refreshLocalizedContent()
            settingsWindowController?.refreshLocalizedContent()
        case .applicationSortOrder:
            refreshPresentedCatalog(animated: true)
            settingsWindowController?.refreshLocalizedContent()
        case .hotKey:
            settingsWindowController?.refreshLocalizedContent()
        case .fourFingerPinch:
            gestureMonitorController?.setEnabled(preferences.fourFingerPinchEnabled)
            settingsWindowController?.refreshLocalizedContent()
        }
    }

    private func refreshPresentedCatalog(animated: Bool) {
        window?.update(
            items: presentedItems(from: canonicalItems),
            catalogChanged: animated,
            invalidatedIconPaths: []
        )
    }

    private func presentedItems(from items: [LunchpadItem]) -> [LunchpadItem] {
        ApplicationOrderingPolicy.apply(
            to: items,
            order: preferences.applicationSortOrder,
            locale: localizer.resolvedLanguage.locale,
            otherFolderName: localizer.string("folder.other")
        )
    }

    private func toggleLunchpad() {
        guard let window else { return }
        if window.isVisible {
            window.close()
        } else {
            showLunchpad()
        }
    }

    private func printGestureDebugFrame(_ frame: MultitouchFrame) {
        let contacts = frame.activeContacts
        let now = ProcessInfo.processInfo.systemUptime

        if contacts.count != debugLastContactCount {
            print("[Gesture] records=\(frame.contacts.count) active=\(contacts.count)")
            debugLastContactCount = contacts.count
        }

        guard contacts.count == 4 else {
            debugMaximumDistance = nil
            return
        }

        var distance = 0.0
        var pairCount = 0
        for first in contacts.indices {
            for second in contacts.indices where second > first {
                distance += hypot(
                    contacts[first].x - contacts[second].x,
                    contacts[first].y - contacts[second].y
                )
                pairCount += 1
            }
        }
        distance /= Double(pairCount)
        debugMaximumDistance = max(debugMaximumDistance ?? distance, distance)

        if now - debugLastPrintAt >= 0.1, let debugMaximumDistance {
            print(
                "[Gesture] four-finger spread=\(String(format: "%.3f", distance)) "
                    + "ratio=\(String(format: "%.3f", distance / debugMaximumDistance))"
            )
            debugLastPrintAt = now
        }
    }
}
