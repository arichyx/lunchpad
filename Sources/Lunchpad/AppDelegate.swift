import AppKit
import DesktopStateKit
import MultitouchKit

enum CatalogRefreshLayoutRebaser {
    static func rebase(
        scannedItems: [LunchpadItem],
        on layoutStore: LunchpadLayoutStore
    ) throws -> [LunchpadItem] {
        AppScanner.applyingRuntimeMetadata(
            to: try layoutStore.loadVisibleItems(),
            from: scannedItems.flatMap(\.apps)
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = LunchpadPreferences()
    private lazy var localizer = AppLocalizer(language: preferences.interfaceLanguage)
    private var window: LunchpadWindow?
    private var canonicalItems: [LunchpadItem] = []
    private var layoutStore: LunchpadLayoutStore?
    private var catalogSynchronizer: ApplicationCatalogSynchronizer?
    private var hotKeyController: HotKeyController?
    private let loginItemController = LoginItemController()
    private var gestureMonitorController: GestureMonitorController?
    private var multitouchDeviceObserver: MultitouchDeviceObserver?
    private var wakeObserver: NSObjectProtocol?
    private var settingsWindowController: SettingsWindowController?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var activeSpaceChangeObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
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
        do {
            let openedStore = try LunchpadLayoutStore()
            layoutStore = openedStore
            Log.layout.notice("Layout database: \(openedStore.databaseURL.path)")
        } catch {
            Log.layout.error("Layout database unavailable, using flat layout: \(error)")
        }

        let synchronizer = ApplicationCatalogSynchronizer(
            scanner: scanner,
            layoutStore: layoutStore
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
            Log.catalog.notice("Application directory monitor started")
        } catch {
            Log.catalog.error("Failed to start application directory monitor: \(error)")
        }
        catalogSynchronizer = synchronizer

        // Restore logical folders from SQLite after scanning; Finder directories are not folders.
        let initialCatalog = synchronizer.loadInitialCatalog()
        if !initialCatalog.usesPersistentLayout {
            layoutStore = nil
        }
        let items = initialCatalog.items
        canonicalItems = items
        let appCount = items.reduce(0) { $0 + $1.apps.count }
        let folderCount = items.reduce(0) { count, item in
            if case .folder = item { return count + 1 }
            return count
        }
        Log.catalog.notice("Scan complete: \(appCount) apps, \(folderCount) folders")
        window = LunchpadWindow(
            items: presentedItems(from: items),
            localizer: localizer,
            rootPageStore: RootPageStore(),
            allowsDragArrangement: initialCatalog.usesPersistentLayout
        )
        window?.onDragCommit = { [weak self] commit in
            self?.handleDragCommit(commit)
        }
        window?.onLaunchFailure = { [weak self] app, error in
            self?.presentLaunchFailure(for: app, error: error)
        }
        window?.onFolderRename = { [weak self] identifier, name in
            self?.applyLayoutEdit("Folder rename") { store in
                try store.renameFolder(identifier: identifier, name: name)
            }
        }
        window?.onFolderDelete = { [weak self] identifier in
            self?.applyLayoutEdit("Folder deletion") { store in
                try store.deleteFolder(identifier: identifier)
            }
        }

        installStatusItem()
        installApplicationMenu()
        installGlobalHotKey()
        installMultitouchMonitor()
        installWorkspaceActivationObserver()
        installActiveSpaceChangeObserver()
        installScreenParametersObserver()
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
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        multitouchDeviceObserver = nil
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
                Log.hotKey.error("Global hot key registration failed: \(error)")
            } else {
                Log.hotKey.notice("Global hot key disabled")
            }
            return
        }

        if controller.isExternallyManaged {
            Log.hotKey.notice(
                "Global hot key registered from LUNCHPAD_HOTKEY: \(configuration.displayName)"
            )
        } else {
            Log.hotKey.notice("Global hot key registered: \(configuration.displayName)")
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

    /// Follows display reconfigurations while the launcher is visible; see
    /// `LunchpadWindow.screenParametersDidChange()`.
    private func installScreenParametersObserver() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window?.screenParametersDidChange()
            }
        }
    }

    private func installMultitouchMonitor() {
        let controller = GestureMonitorController { [weak self] monitor, fingerCount in
            self?.configureMultitouchMonitor(monitor, fingerCount: fingerCount)
        }
        gestureMonitorController = controller
        let fingerCount = preferences.gestureFingerCount.rawValue
        controller.setConfiguration(
            enabled: preferences.gestureEnabled,
            fingerCount: fingerCount
        )
        if let error = controller.lastErrorDescription {
            Log.gesture.error("Trackpad gesture monitor failed to start: \(error)")
        } else if controller.isMonitoring {
            Log.gesture.notice("\(fingerCount)-finger trackpad gesture monitor started")
        }
        installMultitouchRecovery()
    }

    /// Rebuilds the gesture monitor after wake and whenever a multitouch device appears or
    /// disappears, so a lost driver stream or a reconnected trackpad does not leave gestures
    /// unavailable until the user toggles the setting.
    private func installMultitouchRecovery() {
        do {
            multitouchDeviceObserver = try MultitouchDeviceObserver { [weak self] in
                MainActor.assumeIsolated {
                    Log.gesture.notice(
                        "Multitouch device changed; restarting the trackpad gesture monitor"
                    )
                    self?.scheduleGestureMonitorRestart()
                }
            }
        } catch {
            Log.gesture.error("Multitouch device notifications unavailable: \(error)")
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleGestureMonitorRestart()
            }
        }
    }

    private func scheduleGestureMonitorRestart() {
        gestureMonitorController?.scheduleRestart { [weak self] in
            guard let self, let controller = self.gestureMonitorController else { return }
            if let error = controller.lastErrorDescription {
                Log.gesture.error("Trackpad gesture monitor failed to restart: \(error)")
            }
            self.settingsWindowController?.refreshLocalizedContent()
        }
    }

    private func configureMultitouchMonitor(
        _ monitor: any GestureMonitoring,
        fingerCount: Int
    ) {
        let gestureDebugEnabled = ProcessInfo.processInfo.environment[
            "LUNCHPAD_GESTURE_DEBUG"
        ] == "1"

        // Only the system's four-finger inward gesture restores Show Desktop. Three-finger mode
        // is independent and must remain available while the desktop is shown.
        if fingerCount == GestureFingerCount.four.rawValue {
            let showDesktopStateDetector = ShowDesktopStateDetector()
            monitor.shouldActivatePinch = {
                let evaluation = showDesktopStateDetector.evaluate()
                if gestureDebugEnabled {
                    Log.gesture.debug(
                        "[Gesture] showDesktop=\(evaluation.isActive) "
                            + "visible=\(evaluation.visibleWindowCount) "
                            + "displaced=\(evaluation.displacedWindowCount)"
                    )
                }
                return !evaluation.isActive
            }
            monitor.onPinchSuppressed = {
                Log.gesture.notice("Show Desktop is active; leaving this four-finger pinch to macOS")
            }
        }
        monitor.onPinch = { [weak self] in
            Log.gesture.notice("\(fingerCount)-finger pinch completed; showing Lunchpad")
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Resolve the pointer's display on the main actor so AppKit APIs are reached
                // safely and the screen list cannot change between sampling and presentation.
                self.showLunchpad(targetScreen: self.screenForPointer())
            }
        }
        monitor.onExpand = { [weak self] in
            Log.gesture.notice("\(fingerCount)-finger spread completed; hiding Lunchpad")
            Task { @MainActor [weak self] in
                self?.dismissLunchpad()
            }
        }
        if gestureDebugEnabled {
            monitor.onFrame = { [weak self] frame in
                Task { @MainActor [weak self] in
                    self?.printGestureDebugFrame(frame, fingerCount: fingerCount)
                }
            }
        }
        monitor.onError = { [weak self, weak monitor] error in
            Log.gesture.error("Trackpad data stream stopped: \(error)")
            Task { @MainActor [weak self, weak monitor] in
                // A released monitor was already replaced; its late error is irrelevant.
                guard let self, let monitor else { return }
                self.gestureMonitorController?.reportRuntimeError(error, from: monitor)
                self.settingsWindowController?.refreshLocalizedContent()
            }
        }
    }

    /// Hot key, status item, and menu activations present on the pointer's display, like the
    /// trackpad pinch.
    private func showLunchpad() {
        showLunchpad(targetScreen: screenForPointer())
    }

    private func showLunchpad(targetScreen: NSScreen?) {
        guard let window, !window.isVisible else { return }
        settingsWindowController?.window?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.show(on: targetScreen)
    }

    /// Resolves the screen that should host the launcher for any activation path.
    ///
    /// Samples `NSEvent.mouseLocation` on the main actor (the multitouch callback is off-thread)
    /// and selects the connected display whose frame contains that point. Falls back to
    /// `NSScreen.main`, then to `nil` (which lets `LunchpadWindow.show` keep its previous
    /// main-screen behavior) when no screen contains the pointer.
    private func screenForPointer() -> NSScreen? {
        let pointerLocation = NSEvent.mouseLocation
        return ScreenSelectionPolicy.selectedScreen(
            pointerLocation: pointerLocation,
            screens: NSScreen.screens,
            mainScreen: NSScreen.main
        )
    }

    /// Lunchpad closes before Launch Services answers, so a failed launch would otherwise go
    /// unnoticed.
    private func presentLaunchFailure(for app: AppItem, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizer.formatted("launch.failed.title", app.name)
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: localizer.string("alert.ok"))
        NSApp.activate()
        alert.runModal()
    }

    private func dismissLunchpad() {
        guard let window, window.isVisible else { return }
        window.close()
    }

    /// Persists a completed drag arrangement and keeps the presented catalog in step.
    ///
    /// The store's positions become the presented order in Manual mode, so the first drag under
    /// an automatic ordering mode selects Manual without visibly re-sorting the grid. A commit
    /// is serialized with background reconciliation; a genuinely stale arrangement still throws,
    /// and the presented catalog is restored unchanged.
    private func handleDragCommit(_ commit: LunchpadDragCommit) {
        guard let layoutStore else {
            refreshPresentedCatalog(animated: false)
            return
        }
        do {
            try layoutStore.commit(commit)
            let arrangedItems = try layoutStore.loadVisibleItems()
            canonicalItems = AppScanner.applyingRuntimeMetadata(
                to: arrangedItems,
                from: canonicalItems.flatMap(\.apps)
            )
        } catch {
            Log.layout.error("Drag arrangement was not saved: \(error)")
            refreshPresentedCatalog(animated: false)
            return
        }

        if preferences.applicationSortOrder != .manual {
            preferences.applicationSortOrder = .manual
        } else {
            refreshPresentedCatalog(animated: false)
        }
    }

    /// Persists a folder edit and presents the stored layout. A failed edit leaves the stored
    /// layout unchanged, and the presented catalog is restored from it.
    private func applyLayoutEdit(
        _ description: String,
        _ edit: (LunchpadLayoutStore) throws -> Void
    ) {
        guard let layoutStore else {
            refreshPresentedCatalog(animated: false)
            return
        }
        do {
            try edit(layoutStore)
            canonicalItems = AppScanner.applyingRuntimeMetadata(
                to: try layoutStore.loadVisibleItems(),
                from: canonicalItems.flatMap(\.apps)
            )
        } catch {
            Log.layout.error("\(description) was not saved: \(error)")
        }
        refreshPresentedCatalog(animated: false)
    }

    private func applyCatalogRefresh(
        _ items: [LunchpadItem],
        catalogChanged: Bool,
        invalidatedIconPaths: Set<String>?
    ) {
        let latestItems: [LunchpadItem]
        if let layoutStore {
            do {
                // The scan completed off-main and its callback may arrive after a drag commit.
                // Re-read positions now, then retain fresh filesystem metadata from the scan.
                latestItems = try CatalogRefreshLayoutRebaser.rebase(
                    scannedItems: items,
                    on: layoutStore
                )
            } catch {
                Log.catalog.error("Failed to apply application catalog refresh: \(error)")
                return
            }
        } else {
            latestItems = items
        }

        canonicalItems = latestItems
        let appCount = latestItems.reduce(0) { $0 + $1.apps.count }
        let reason = catalogChanged ? "catalog change" : "app content change"
        Log.catalog.notice("Application catalog synchronized (\(reason)): \(appCount) apps")
        window?.update(
            items: presentedItems(from: latestItems),
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
        case .gestureEnabled, .gestureFingerCount:
            gestureMonitorController?.setConfiguration(
                enabled: preferences.gestureEnabled,
                fingerCount: preferences.gestureFingerCount.rawValue
            )
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

    private func printGestureDebugFrame(_ frame: MultitouchFrame, fingerCount: Int) {
        let contacts = frame.activeContacts
        let now = ProcessInfo.processInfo.systemUptime

        if contacts.count != debugLastContactCount {
            Log.gesture.debug("[Gesture] records=\(frame.contacts.count) active=\(contacts.count)")
            debugLastContactCount = contacts.count
        }

        guard contacts.count == fingerCount else {
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
            Log.gesture.debug(
                "[Gesture] \(fingerCount)-finger spread=\(String(format: "%.3f", distance)) "
                    + "ratio=\(String(format: "%.3f", distance / debugMaximumDistance))"
            )
            debugLastPrintAt = now
        }
    }
}
