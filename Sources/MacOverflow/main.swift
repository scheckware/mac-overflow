import AppKit
import ApplicationServices
import MacOverflowCore
import SwiftUI

// Pure AppKit entry point. This is a menu bar agent with nothing to configure,
// so there's no SwiftUI `Settings` scene (which would add an empty "Mac Overflow
// Settings" window). SwiftUI is still used for the All Items window via
// NSHostingController.
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let overflowMenu = NSMenu()
    private let monitor = MenuBarMonitor()
    private var menuIsOpen = false
    private var allItemsWindow: NSWindow?
    /// True from when the menu opens until that open's fresh scan lands. While
    /// set, the menu shows "Scanning…" rather than a stale cached list.
    private var awaitingScan = false
    /// Set at launch; when the next scan lands, check whether our own ≡ icon is
    /// itself hidden and, if so, open the All Items window.
    private var pendingSelfHiddenCheck = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "line.3.horizontal",
            accessibilityDescription: "Overflow Menu"
        )

        overflowMenu.delegate = self
        statusItem.menu = overflowMenu

        // When a scan finishes: first run the one-time self-hidden check (may run
        // while no menu is open); then, if the menu is open awaiting results,
        // replace the "Scanning…" placeholder with this open's fresh results (a
        // grow, never a shrink).
        monitor.onUpdate = { [weak self] in
            guard let self else { return }
            if self.pendingSelfHiddenCheck {
                self.pendingSelfHiddenCheck = false
                self.openAllItemsIfSelfHidden()
            }
            guard self.menuIsOpen, self.awaitingScan else { return }
            self.awaitingScan = false
            self.populate(self.overflowMenu)
        }

        promptForAccessibilityIfNeeded()

        // No launch warm-up scan for the menu (the menu bar is still settling right
        // after login, so an early scan captures wrong positions). But do one
        // delayed scan to detect whether our own ≡ icon is overflowed/hidden.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.pendingSelfHiddenCheck = true
            self.monitor.refresh()
        }
    }

    /// If our own status item is hidden/overflowed, surface the app by opening the
    /// All Items window (it lists Mac Overflow under Hidden). An off-screen status
    /// item can't be clicked, so this is the only reliable way to reach the app.
    private func openAllItemsIfSelfHidden() {
        let mine = monitor.allItems.first { $0.ownerPID == getpid() }
        if let mine, !mine.isVisibleInBar {
            showAllItems()
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        awaitingScan = true // Show fresh results for this open, not a stale cache.
        monitor.refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        awaitingScan = false
    }

    /// Builds the menu. Shows "Scanning…" until this open's fresh scan lands,
    /// then the current hidden items. Never performs Accessibility IPC itself, so
    /// it can't block the menu-tracking run loop.
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        guard AXIsProcessTrusted() else {
            addItem(to: menu, title: "Grant Accessibility permission…", action: #selector(openAccessibilitySettings))
            addFooter(to: menu)
            return
        }

        // Waiting for this open's fresh scan — don't show a stale cached list.
        if awaitingScan {
            let placeholder = NSMenuItem(title: "Scanning…", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
            addFooter(to: menu)
            return
        }

        let hidden = monitor.hiddenItems.filter { NSRunningApplication(processIdentifier: $0.ownerPID) != nil }
        if hidden.isEmpty {
            let placeholder = NSMenuItem(title: "No hidden items", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        } else {
            for item in hidden {
                let menuItem = addItem(to: menu, title: item.title, action: #selector(handleOverflowItemClick(_:)))
                menuItem.representedObject = item
                menuItem.image = item.icon.map(Self.menuSized)
            }
        }

        addFooter(to: menu)
    }

    // MARK: - Menu construction helpers

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func addFooter(to menu: NSMenu) {
        menu.addItem(.separator())
        addItem(to: menu, title: "All Menu Bar Items…", action: #selector(showAllItems))
        addItem(to: menu, title: "Rescan", action: #selector(rescan), key: "r")
        addItem(to: menu, title: "About Mac Overflow", action: #selector(showAbout))
        addItem(to: menu, title: "Quit", action: #selector(quit), key: "q")
    }

    /// Returns a menu-bar-sized copy of an icon (leaves the original untouched).
    private static func menuSized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 18, height: 18)
        return copy
    }

    // MARK: - Actions

    @objc private func handleOverflowItemClick(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? MenuBarItem else { return }
        item.performClick() // no-op for our own item (self-AX would deadlock)
        // The target app may have opened a panel or quit — refresh shortly after
        // so the list reflects the new state next time the menu opens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.monitor.refresh()
        }
    }

    @objc private func rescan() {
        monitor.refresh()
    }

    @objc private func showAllItems() {
        monitor.refresh()
        if allItemsWindow == nil {
            let controller = NSHostingController(
                rootView: AllItemsView(monitor: monitor, onActivateSelf: { [weak self] in
                    self?.showOverflowMenu()
                })
            )
            let window = NSWindow(contentViewController: controller)
            window.title = "All Menu Bar Items"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 360, height: 460))
            window.isReleasedWhenClosed = false
            allItemsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        allItemsWindow?.center()
        allItemsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Shows our own overflow menu via AppKit (no Accessibility on ourselves).
    /// Used when the user activates the Mac Overflow row in the All Items window,
    /// including when our ≡ icon itself is hidden.
    private func showOverflowMenu() {
        guard let button = statusItem.button else { return }
        if button.window != nil {
            // Our icon is on-screen: click it to open the menu in place.
            button.performClick(nil)
        } else {
            // Off-screen/hidden: pop the menu at the mouse location instead.
            overflowMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let alert = NSAlert()
        alert.messageText = "Mac Overflow"
        alert.informativeText = """
        Lightweight menu bar overflow manager

        Version \(short) (build \(build))
        Scheckware fork · MIT License

        Never lose your menu bar icons again!
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Permissions

    /// Prompts for Accessibility on first launch. The app keeps running if it's
    /// denied — the menu re-checks each time it opens and shows a "grant
    /// permission" entry until access is available.
    private func promptForAccessibilityIfNeeded() {
        // "AXTrustedCheckOptionPrompt" is the documented value of
        // `kAXTrustedCheckOptionPrompt`; using the literal avoids referencing a
        // non-concurrency-safe imported global under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
