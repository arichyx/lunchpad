import AppKit
import MultitouchKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: LunchpadWindow?
    private var catalogSynchronizer: ApplicationCatalogSynchronizer?
    private var globalHotKey: GlobalHotKey?
    private var multitouchMonitor: MultitouchMonitor?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var debugLastContactCount = -1
    private var debugMaximumDistance: Double?
    private var debugLastPrintAt = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        let appCount = items.reduce(0) { $0 + $1.apps.count }
        let folderCount = items.reduce(0) { count, item in
            if case .folder = item { return count + 1 }
            return count
        }
        print("扫描完成：\(appCount) 个应用，\(folderCount) 个文件夹")
        window = LunchpadWindow(items: items)

        installStatusItem()
        installGlobalHotKey()
        installMultitouchMonitor()
        installWorkspaceActivationObserver()
    }

    func applicationWillTerminate(_ notification: Notification) {
        catalogSynchronizer?.stop()
        multitouchMonitor?.stop()
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installGlobalHotKey() {
        guard let configuration = HotKeyConfiguration.load() else {
            print("全局快捷键已禁用")
            return
        }

        do {
            globalHotKey = try GlobalHotKey(configuration: configuration) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.toggleLunchpad()
                }
            }
            print("全局快捷键已注册：\(configuration.displayName)")
        } catch {
            print("⚠️ 注册全局快捷键失败：\(error)")
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let image = NSImage(
                systemSymbolName: "square.grid.3x3.fill",
                accessibilityDescription: "Lunchpad"
            )?.withSymbolConfiguration(configuration)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "Lunchpad"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()
        let showItem = NSMenuItem(
            title: "Show Lunchpad",
            action: #selector(showLunchpadFromStatusItem(_:)),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Lunchpad",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusMenu = menu
        statusItem = item
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

    private func installMultitouchMonitor() {
        let monitor = MultitouchMonitor(fingerCount: 4)
        monitor.onPinch = { [weak self] in
            print("检测到完整四指捏合，手指已抬起，显示 Lunchpad")
            Task { @MainActor [weak self] in
                self?.showLunchpad()
            }
        }
        if ProcessInfo.processInfo.environment["LUNCHPAD_GESTURE_DEBUG"] == "1" {
            monitor.onFrame = { [weak self] frame in
                Task { @MainActor [weak self] in
                    self?.printGestureDebugFrame(frame)
                }
            }
        }
        monitor.onError = { error in
            print("⚠️ 触控板数据流中断：\(error)")
        }

        do {
            try monitor.start()
            multitouchMonitor = monitor
            print("四指捏合监听已启动")
        } catch {
            // The global hot key remains available when the IOKit path cannot start.
            print("⚠️ 四指捏合监听启动失败：\(error)")
        }
    }

    private func showLunchpad() {
        guard let window, !window.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.show()
    }

    private func applyCatalogRefresh(
        _ items: [LunchpadItem],
        catalogChanged: Bool,
        invalidatedIconPaths: Set<String>?
    ) {
        let appCount = items.reduce(0) { $0 + $1.apps.count }
        let reason = catalogChanged ? "目录变化" : "应用内容变化"
        print("应用目录已同步（\(reason)）：\(appCount) 个应用")
        window?.update(
            items: items,
            catalogChanged: catalogChanged,
            invalidatedIconPaths: invalidatedIconPaths
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
