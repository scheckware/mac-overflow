import CoreGraphics

/// Snapshot of the menu bar's geometry, captured on the main actor and handed to
/// the (off-main) scan so item visibility can be judged without touching AppKit.
public struct MenuBarLayout: Sendable {
    /// Screen frames, used for the horizontal-range test (X is identical in
    /// AppKit and Accessibility coordinate spaces).
    public let screenFrames: [CGRect]
    /// Menu bar height. Visible items have a top edge at roughly `y = 0…thickness`.
    public let menuBarThickness: CGFloat
    /// Right edge of the frontmost app's menus. Items whose center is left of
    /// this are painted over by those menus. `0` disables the check.
    public let appMenuRightEdge: CGFloat
    /// Horizontal span of the display notch. When `notchMaxX > notchMinX`, the
    /// display has a notch. Equal values = no notch.
    public let notchMinX: CGFloat
    public let notchMaxX: CGFloat
    /// Left edge (X origin) of the screen that has the notch. Used to scope the
    /// notch rule to that screen so external displays aren't affected.
    public let notchScreenMinX: CGFloat

    public init(
        screenFrames: [CGRect],
        menuBarThickness: CGFloat,
        appMenuRightEdge: CGFloat = 0,
        notchMinX: CGFloat = 0,
        notchMaxX: CGFloat = 0,
        notchScreenMinX: CGFloat = 0
    ) {
        self.screenFrames = screenFrames
        self.menuBarThickness = menuBarThickness
        self.appMenuRightEdge = appMenuRightEdge
        self.notchMinX = notchMinX
        self.notchMaxX = notchMaxX
        self.notchScreenMinX = notchScreenMinX
    }
}

/// Pure geometry helpers for deciding whether a menu bar item is on-screen.
///
/// Kept free of AppKit/Accessibility so it can be unit-tested without a live
/// window server or granted permissions.
public enum MenuBarGeometry {
    /// macOS leaves a gap so status items don't render flush against the notch.
    /// An item must clear the notch's right edge by at least this much to count
    /// as visible.
    private static let notchGuard: CGFloat = 24

    /// Returns whether a menu bar item is currently **visible** in the menu bar.
    ///
    /// An item is visible only when it sits in the menu bar band (X on a screen,
    /// top edge near `y = 0`) **and** isn't occluded by the frontmost app's menus
    /// (left) or the display notch. On a notched display, real status items live
    /// to the *right* of the notch, so anything whose left edge doesn't clear the
    /// notch's right edge (plus a small guard band) is treated as hidden — macOS
    /// parks overflowed items there with normal-looking coordinates.
    ///
    /// - Note: The vertical test assumes the primary display's menu bar (AX
    ///   `y ≈ 0`); items on a secondary display's menu bar may be misclassified.
    public static func isVisible(itemFrame: CGRect, layout: MenuBarLayout) -> Bool {
        guard itemFrame.width > 0, itemFrame.height > 0 else { return false }

        // Must sit in the menu bar band at the top of the display.
        guard itemFrame.minY >= -2, itemFrame.minY <= layout.menuBarThickness else { return false }

        let centerX = itemFrame.midX

        if layout.notchMaxX > layout.notchMinX {
            // Notched display: the notch is the authoritative left boundary. The
            // frontmost app's menu width is irrelevant here (app menus live left
            // of the notch) — and consulting it would make results depend on
            // which app is frontmost at scan time, so the menu and the "All
            // Items" window could disagree. Item must clear the notch on the right.
            if centerX >= layout.notchScreenMinX,
               itemFrame.minX <= layout.notchMaxX + notchGuard {
                return false
            }
        } else {
            // No notch: items can be painted over by the frontmost app's menus.
            if centerX < layout.appMenuRightEdge { return false }
        }

        return layout.screenFrames.contains { frame in
            centerX >= frame.minX && centerX <= frame.maxX
        }
    }
}
