import CoreGraphics
import XCTest
@testable import MacOverflowCore

final class MenuBarGeometryTests: XCTestCase {
    private let mainScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let menuBarThickness: CGFloat = 24

    private func isVisible(
        _ frame: CGRect,
        screens: [CGRect]? = nil,
        appMenuRightEdge: CGFloat = 0,
        notch: (CGFloat, CGFloat) = (0, 0)
    ) -> Bool {
        MenuBarGeometry.isVisible(
            itemFrame: frame,
            layout: MenuBarLayout(
                screenFrames: screens ?? [mainScreen],
                menuBarThickness: menuBarThickness,
                appMenuRightEdge: appMenuRightEdge,
                notchMinX: notch.0,
                notchMaxX: notch.1
            )
        )
    }

    // A normal on-bar item: X within the screen, Y at the top (~2.5).
    func testItemInMenuBarIsVisible() {
        XCTAssertTrue(isVisible(CGRect(x: 1200, y: 2.5, width: 24, height: 22)))
    }

    func testItemPushedOffLeftEdgeIsHidden() {
        // center x = -28
        XCTAssertFalse(isVisible(CGRect(x: -40, y: 2.5, width: 24, height: 22)))
    }

    func testItemBeyondRightEdgeIsHidden() {
        // center x = 1462, past maxX (1440)
        XCTAssertFalse(isVisible(CGRect(x: 1450, y: 2.5, width: 24, height: 22)))
    }

    // Real case from diagnostics: JetBrains Toolbox parked above the screen.
    func testItemAboveScreenIsHidden() {
        XCTAssertFalse(isVisible(CGRect(x: 1080, y: -76, width: 24, height: 24)))
    }

    // Real case: items parked near the bottom (y≈965) though X is on-screen.
    func testItemBelowMenuBarIsHidden() {
        XCTAssertFalse(isVisible(CGRect(x: 7, y: 965, width: 24, height: 24)))
    }

    func testItemJustInsideMenuBarBandIsVisible() {
        XCTAssertTrue(isVisible(CGRect(x: 800, y: 3.5, width: 22, height: 22)))
    }

    func testZeroSizeItemIsHidden() {
        XCTAssertFalse(isVisible(CGRect(x: 1200, y: 2.5, width: 0, height: 0)))
    }

    func testItemVisibleOnSecondaryScreen() {
        let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(isVisible(CGRect(x: 3000, y: 2.5, width: 24, height: 22), screens: [mainScreen, secondary]))
    }

    func testNoScreensMeansHidden() {
        XCTAssertFalse(isVisible(CGRect(x: 100, y: 2.5, width: 24, height: 22), screens: []))
    }

    // Real case: at width 1168 the app menus extended to ~495, painting over
    // ClipboardHistory (x:472, center 483) though its coords look on-bar.
    func testItemBehindAppMenusIsHidden() {
        XCTAssertFalse(isVisible(CGRect(x: 472, y: 2, width: 22, height: 22), appMenuRightEdge: 495))
    }

    func testItemRightOfAppMenusIsVisible() {
        // AppleConnect at x:501 (center 537) sat just right of the menus.
        XCTAssertTrue(isVisible(CGRect(x: 501, y: 1, width: 72, height: 24), appMenuRightEdge: 495))
    }

    // On a notched display (notch spans 1000…1100), only items that clear the
    // notch's right edge (plus guard band) are actually drawn.
    func testItemUnderNotchIsHidden() {
        XCTAssertFalse(isVisible(CGRect(x: 1039, y: 2, width: 22, height: 22), notch: (1000, 1100)))
    }

    func testItemLeftOfNotchIsHidden() {
        // Real case: ClipboardHistory at x:428, left of a notch at 521…646.
        XCTAssertFalse(isVisible(CGRect(x: 428, y: 2, width: 22, height: 22), notch: (521, 646)))
    }

    // Real case: Shottr at x:653 is only 7px past the notch edge (646) — cut off.
    func testItemAdjacentToNotchIsHidden() {
        XCTAssertFalse(isVisible(CGRect(x: 653, y: 1, width: 24, height: 24), notch: (521, 646)))
    }

    // Real case: Token Meter at x:683 clears the notch guard band — visible.
    func testItemClearOfNotchIsVisible() {
        XCTAssertTrue(isVisible(CGRect(x: 683, y: 1, width: 70, height: 24), notch: (521, 646)))
    }

    func testItemFarRightOfNotchIsVisible() {
        XCTAssertTrue(isVisible(CGRect(x: 1200, y: 2, width: 22, height: 22), notch: (1000, 1100)))
    }

    // Regression: on a notched display the app-menu width must be ignored, so
    // classification doesn't depend on which app is frontmost at scan time (that
    // made the ≡ menu and the All Items window disagree). An item right of the
    // notch stays visible even with a huge appMenuRightEdge.
    func testNotchIgnoresAppMenuEdge() {
        XCTAssertTrue(isVisible(
            CGRect(x: 700, y: 2, width: 22, height: 22),
            appMenuRightEdge: 2000,
            notch: (521, 646)
        ))
    }
}
