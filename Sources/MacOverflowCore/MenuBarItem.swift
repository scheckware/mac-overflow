import AppKit
import ApplicationServices

/// A single menu bar status item ("menu bar extra") vended by another app.
///
/// Immutable and read-only, so it's safe to hand between the background scan
/// and the main actor (`@unchecked` because it holds an `AXUIElement`/`NSImage`,
/// which aren't formally `Sendable`).
public struct MenuBarItem: Identifiable, @unchecked Sendable {
    public let id: String
    /// Human-readable label: the item's title, its description, or, failing
    /// both, the name of the app that owns it.
    public let title: String
    /// Localized name of the app that owns the item.
    public let ownerName: String
    /// Process id of the owning app (used to prune items whose app has quit).
    public let ownerPID: pid_t
    /// An icon for the menu entry: the item's own AX image when available,
    /// otherwise the owning app's icon.
    public let icon: NSImage?
    /// The item's frame in screen coordinates, as reported by Accessibility.
    public let frame: CGRect
    /// Whether the item is currently drawn in the menu bar. Set by the scan.
    public internal(set) var isVisibleInBar: Bool = false

    /// The underlying accessibility element, used to forward clicks.
    let element: AXUIElement

    /// Forwards a click to the real menu bar item.
    ///
    /// Menu bar extras respond to different actions, so try them in turn: a
    /// press (toggles/activates most items), then "show menu" (for items that
    /// present a menu), then pressing a child element (some items delegate to a
    /// button). Returns `false` if none were accepted.
    @discardableResult
    public func performClick() -> Bool {
        // Never AX-press our own status item: it's a synchronous, main-thread AX
        // call targeting our own process, which deadlocks. Callers should also
        // avoid offering self as a click target, but this is the hard backstop.
        guard ownerPID != getpid() else { return false }
        if AX.perform(element, kAXPressAction as String) { return true }
        if AX.perform(element, kAXShowMenuAction as String) { return true }
        for child in AX.children(element) {
            if AX.perform(child, kAXPressAction as String) { return true }
        }
        return false
    }
}

extension MenuBarItem {
    /// Builds a `MenuBarItem` from an AX element, or returns `nil` if the
    /// element lacks a usable position/size (and therefore isn't a real item).
    static func from(element: AXUIElement, ownerName: String, ownerPID: pid_t, ownerIcon: NSImage?) -> MenuBarItem? {
        guard let position = AX.point(element, kAXPositionAttribute as String),
              let size = AX.size(element, kAXSizeAttribute as String) else {
            return nil
        }

        let title = resolveTitle(element: element, ownerName: ownerName)

        // AXImage rarely resolves to an NSImage for status items; when it
        // doesn't, the owning app's icon is a recognizable stand-in.
        let axImage: NSImage? = AX.attribute(element, "AXImage")

        // Title can be empty or change over time, so anchor identity on the
        // owner plus the item's rounded position.
        let id = "\(ownerName)@\(Int(position.x)),\(Int(position.y))"

        return MenuBarItem(
            id: id,
            title: title,
            ownerName: ownerName,
            ownerPID: ownerPID,
            icon: axImage ?? ownerIcon,
            frame: CGRect(origin: position, size: size),
            element: element
        )
    }

    /// Finds the most descriptive label for an item. On macOS 26, Control
    /// Center owns most items and leaves `title` empty, so fall through to
    /// description/help/identifier and finally a child element's label before
    /// giving up and using the owning app's name.
    private static func resolveTitle(element: AXUIElement, ownerName: String) -> String {
        let candidates: [String?] = [
            AX.attribute(element, kAXTitleAttribute as String),
            AX.attribute(element, kAXDescriptionAttribute as String),
            AX.attribute(element, "AXHelp"),
            AX.attribute(element, "AXIdentifier"),
        ]
        for case let candidate? in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        // Some items carry their label on a child element instead.
        for child in AX.children(element) {
            if let desc: String = AX.attribute(child, kAXDescriptionAttribute as String),
               !desc.isEmpty {
                return desc
            }
            if let childTitle: String = AX.attribute(child, kAXTitleAttribute as String),
               !childTitle.isEmpty {
                return childTitle
            }
        }

        return ownerName
    }
}
