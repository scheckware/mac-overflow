import AppKit
import ApplicationServices
import Combine

/// A minimal, `Sendable` snapshot of a running app, captured on the main actor
/// so the background scan never has to touch AppKit app objects off-thread.
private struct AppSnapshot: @unchecked Sendable {
    let pid: pid_t
    let name: String
    let icon: NSImage?
}

/// Thread-safe accumulator for the concurrent scan.
private final class ScanCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var items: [MenuBarItem] = []

    func add(_ newItems: [MenuBarItem]) {
        lock.lock()
        defer { lock.unlock() }
        items.append(contentsOf: newItems)
    }
}

/// Enumerates menu bar status items ("extras") across running apps and reports
/// which are visible vs. hidden (pushed off-screen, behind the app menus, or
/// under the notch).
///
/// The scan runs **off the main thread**. Accessibility calls are synchronous
/// IPC that block until the target app replies or a timeout fires; doing that
/// on the main thread — especially while a status-bar menu is tracking, which
/// holds an input grab — can freeze input system-wide. So the scan is dispatched
/// to a background queue with a strict per-call timeout, and results are
/// published back on the main actor.
@MainActor
public final class MenuBarMonitor: ObservableObject {
    /// Every menu bar extra found by the most recent scan (visible and hidden).
    @Published public private(set) var allItems: [MenuBarItem] = []

    /// Whether a background scan is currently in flight.
    @Published public private(set) var isScanning = false

    /// The hidden subset of ``allItems``.
    public var hiddenItems: [MenuBarItem] {
        allItems.filter { !$0.isVisibleInBar }
    }

    /// Invoked on the main actor whenever ``allItems`` changes (for imperative
    /// UI such as the status-bar `NSMenu`).
    public var onUpdate: (() -> Void)?

    /// Maximum time any single Accessibility call may block. Bounds the damage a
    /// single unresponsive app can do.
    nonisolated private static let axTimeout: Float = 0.25

    private let scanQueue = DispatchQueue(label: "com.omniaura.macoverflow.scan", qos: .userInitiated)

    public init() {}

    /// Starts a background scan of menu bar extras. Does nothing if the app
    /// isn't yet Accessibility-trusted or a scan is already running.
    public func refresh() {
        guard AXIsProcessTrusted(), !isScanning else { return }
        isScanning = true

        // Capture everything the scan needs on the main actor, as Sendable data.
        let screenFrames = NSScreen.screens.map(\.frame)
        let menuBarThickness = NSStatusBar.system.thickness
        let notch = Self.notchInfo()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps: [AppSnapshot] = NSWorkspace.shared.runningApplications.compactMap { app in
            let pid = app.processIdentifier
            guard pid > 0 else { return nil }
            return AppSnapshot(
                pid: pid,
                name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                icon: app.icon
            )
        }

        scanQueue.async { [weak self] in
            let items = MenuBarMonitor.scan(
                apps: apps,
                screenFrames: screenFrames,
                menuBarThickness: menuBarThickness,
                notch: notch,
                frontmostPID: frontmostPID
            )
            Task { @MainActor in
                guard let self else { return }
                self.allItems = items
                self.isScanning = false
                self.onUpdate?()
            }
        }
    }

    /// The display notch's geometry (via public `NSScreen` API): the left edge of
    /// the notched screen and the notch's own X span. All zero if no notch.
    private static func notchInfo() -> (screenMinX: CGFloat, minX: CGFloat, maxX: CGFloat) {
        guard let screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return (0, 0, 0)
        }
        // The notch is the gap between the two areas flanking it.
        return (screen.frame.minX, left.maxX, right.minX)
    }

    // MARK: - Background scan (nonisolated)

    /// Right edge (max X) of the frontmost app's menus. Status items whose
    /// center falls left of this are painted over by those menus.
    nonisolated private static func appMenuRightEdge(pid: pid_t?) -> CGFloat {
        guard let pid else { return 0 }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        guard let menuBar: AXUIElement = AX.attribute(app, kAXMenuBarAttribute as String) else { return 0 }
        var maxX: CGFloat = 0
        for item in AX.children(menuBar) {
            if let position = AX.point(item, kAXPositionAttribute as String),
               let size = AX.size(item, kAXSizeAttribute as String) {
                maxX = max(maxX, position.x + size.width)
            }
        }
        return maxX
    }

    /// Performs the Accessibility enumeration off the main actor.
    ///
    /// Apps are queried **concurrently**: each app's Accessibility IPC (and its
    /// one-time connection setup) is independent, so fanning out across cores
    /// turns a serial ~N×timeout worst case into roughly N/cores.
    nonisolated private static func scan(
        apps: [AppSnapshot],
        screenFrames: [CGRect],
        menuBarThickness: CGFloat,
        notch: (screenMinX: CGFloat, minX: CGFloat, maxX: CGFloat),
        frontmostPID: pid_t?
    ) -> [MenuBarItem] {
        let layout = MenuBarLayout(
            screenFrames: screenFrames,
            menuBarThickness: menuBarThickness,
            appMenuRightEdge: appMenuRightEdge(pid: frontmostPID),
            notchMinX: notch.minX,
            notchMaxX: notch.maxX,
            notchScreenMinX: notch.screenMinX
        )
        let collector = ScanCollector()

        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            collector.add(scanApp(apps[index], layout: layout))
        }

        return collector.items.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Enumerates one app's menu bar extras (visible and hidden).
    nonisolated private static func scanApp(_ app: AppSnapshot, layout: MenuBarLayout) -> [MenuBarItem] {
        let appElement = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(appElement, axTimeout)

        // Most apps have no extras — this returns quickly (or times out fast).
        guard let extras: AXUIElement = AX.attribute(appElement, kAXExtrasMenuBarAttribute as String) else {
            return []
        }

        var items: [MenuBarItem] = []
        for child in AX.children(extras) {
            AXUIElementSetMessagingTimeout(child, axTimeout)

            // Skip empty placeholder slots. Control Center vends several
            // disabled, zero-size items that aren't real menu bar extras.
            let enabled = AX.bool(child, kAXEnabledAttribute as String) ?? true
            guard enabled,
                  var item = MenuBarItem.from(element: child, ownerName: app.name, ownerPID: app.pid, ownerIcon: app.icon),
                  item.frame.width > 0, item.frame.height > 0 else {
                continue
            }

            item.isVisibleInBar = MenuBarGeometry.isVisible(itemFrame: item.frame, layout: layout)
            items.append(item)
        }
        return items
    }
}
