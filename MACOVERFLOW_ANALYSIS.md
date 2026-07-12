# Mac Overflow — Safety, Compatibility & Architecture Analysis

_Analysis date: 2026-07-11. Reviewed: full source tree (`Sources/`, `Tests/`,
`Casks/`) — 3 Swift source files, ~230 lines of real code._

## TL;DR

- **Is it safe?** **Yes — about as safe as a macOS utility gets.** It's a tiny,
  MIT-licensed, dependency-free native Swift app. **No network access at all**
  (the README's "privacy-first, no internet access" claim checks out), no shell
  execution, no dynamic loading, no private APIs, no bundled binaries. It uses only
  stable **public** Accessibility APIs. There is essentially nothing here that could
  behave maliciously.
- **Does it run on macOS 26.5?** **It will run**, but its *effectiveness* on modern
  macOS is doubtful. It targets macOS 13+ and uses only public APIs that aren't going
  anywhere. **However**, its method of finding "hidden" items is naive and likely
  surfaces little or nothing on macOS 26 (see "Big caveat" below) — the very problem
  that forces heavier apps like Ice/menustow to use private window-server APIs.
- **Maturity:** This is an **early prototype / MVP**, not a finished product. ~230
  lines, a placeholder test (`XCTAssertTrue(true)`), a leftover `BartenderLiteTests`
  filename hinting at its origin, and no app-bundle packaging in the repo.

---

## What it is

Mac Overflow (`com.omniaura.mac-overflow`) is a **menu bar overflow viewer**. It puts
a single ≡ (hamburger) icon in the menu bar; clicking it opens a dropdown listing menu
bar items that macOS has pushed off-screen, and clicking an entry forwards a press to
the real item. That's the entire feature set.

- **Language/UI:** Swift 6, SwiftUI + AppKit, accessory (no Dock icon).
- **Build:** Swift Package Manager executable (`swift-tools-version: 6.0`), **zero
  dependencies**.
- **Min OS:** macOS 13.0 (Ventura). Distributed via a Homebrew cask + DMG.
- **License:** MIT.

## How it works (all of it)

The whole app is three files:

| File | Role |
|---|---|
| `Sources/MacOverflow/main.swift` (150 ln) | `@main` SwiftUI `App` + `AppDelegate`. Creates the `NSStatusItem`, builds the dropdown `NSMenu` on click, forwards clicks, shows About/Quit, and prompts for Accessibility permission. |
| `Sources/Services/MenuBarMonitor.swift` (80 ln) | Reads the menu bar via Accessibility and returns items it considers "hidden." |
| `Sources/Models/MenuBarItem.swift` (69 ln) | Value type for one item; builds itself from an `AXUIElement` (title/position/size/icon) and can `performClick()` via `kAXPressAction`. |

**Flow:**
1. On launch, sets `.accessory` policy, creates the ≡ status item, and calls
   `AXIsProcessTrustedWithOptions` to prompt for Accessibility (quits if denied).
2. On click, `MenuBarMonitor.getHiddenMenuBarItems()`:
   - Gets the system-wide element, reads `kAXMenuBarAttribute`, walks its
     `kAXChildrenAttribute`,
   - Builds a `MenuBarItem` per child (title, frame, icon),
   - Sorts by X, and filters to items whose **center X is `<= 0` or `>= screenWidth`**
     — i.e., treats off-screen center as "hidden."
3. Renders those in an `NSMenu`; a click calls `AXUIElementPerformAction(…press…)`.

## Safety analysis

**All clean:**
- **Network:** none. No `URLSession`, no sockets, no telemetry, no update-phone-home.
  The only URL is a `x-apple.systempreferences:` deep link to open the Accessibility
  settings pane.
- **Execution / dynamic code:** none. No `Process`, `NSTask`, `osascript`, `dlopen`,
  `eval`, or base64 payloads.
- **Private APIs:** none. Uses only public `ApplicationServices`/AppKit
  (`AXUIElement*`, `NSStatusItem`, `NSMenu`).
- **Binaries:** none committed. Source-only.
- **Dependencies:** none — nothing to vet or get compromised.
- **Permissions:** only **Accessibility**, requested transparently on first launch.
  No Screen Recording, Input Monitoring, or Post Events.

**Minor supply-chain nit:** `Casks/mac-overflow.rb` uses `sha256 :no_check`, so the
Homebrew cask does **not** verify the downloaded zip's hash. If you install via the
cask, you're trusting the GitHub release asset without integrity pinning. (Building
from this source sidesteps that entirely.)

## macOS 26.5 compatibility

- **Will it launch/run on 26.5?** Yes. Everything it uses is stable public API with a
  macOS 13 floor; nothing here is deprecated or version-fragile.
- **Big caveat — will it actually *work* on 26.5?** Questionable:
  1. `AXUIElementCreateSystemWide()` + `kAXMenuBarAttribute` returns the **focused
     app's application menu** (Apple/File/Edit…), **not** the right-side status
     items / menu bar extras (those live under a different element and are owned by
     other processes — on **macOS 26, Control Center owns them all**). So the monitor
     may be inspecting the wrong menu bar and could return few or no real status items.
  2. Truly overflowed/off-screen items often **aren't exposed via Accessibility at
     all**, so a frame-center test can't "recover" them. This is exactly the wall
     that pushes Ice/menustow toward private `CGS*` window-server APIs + an XPC helper.
- **Net:** it's compatible in the "runs without crashing" sense, but its core promise
  ("never lose your menu bar icons") likely underdelivers on modern macOS **until the
  detection is reworked**. This needs verification on a real 26.5 machine.

## Suggested improvements

**Correctness (the big one)**
1. **Fix item discovery.** Read the status-item side of the menu bar
   (`kAXExtrasMenuBarAttribute` / per-app menu-bar-extras), and validate on macOS 26's
   Control-Center-owned model. Confirm whether AX can even see overflowed items; if
   not, this app's premise needs a different mechanism.
2. **Define "hidden" meaningfully.** The current `centerX > 0 && < screenWidth` test is
   a rough heuristic; account for the notch, multiple displays, and items partially
   clipped.

**Product / robustness**
3. **Real tests.** Replace the placeholder `XCTAssertTrue(true)` (and rename the stray
   `BartenderLiteTests.swift`) with tests over the visibility/sorting logic.
4. **Package a proper `.app`.** As a raw SPM executable there's no bundle Info.plist/
   entitlements/signing in the repo, yet Accessibility trust is keyed to a stable
   signed bundle identity — document or add the packaging step the cask assumes.
5. **Refresh live / handle permission-granted-after-launch** instead of quitting when
   Accessibility is denied.

**Hygiene**
6. **Pin the cask hash** (drop `sha256 :no_check`) once releases are stable.

---

### Verdict

A clean, safe, minimal, easy-to-audit MVP. Its safety and simplicity are its strengths;
its weakness is that the core "find hidden items" logic is naive and probably ineffective
on current macOS (especially macOS 26). Great as a starting point or a
learn-from-it codebase — not yet a dependable daily driver.

---

## Update (2026-07-11): improvements applied

The project **did not compile as downloaded**. The following fixes were applied and
verified (clean Swift 6 build, 0 warnings; 7/7 unit tests passing; universal `.app`
packages correctly):

**Build blockers fixed**
- `MenuBarItem` referenced `kAXImageAttribute`, **a constant that doesn't exist** in the
  SDK → now uses the raw `"AXImage"` attribute string.
- Removed the Swift-5 language-mode workaround; the code now builds under **Swift 6
  strict concurrency** with no warnings. UI code is `@MainActor`, and the
  Accessibility prompt uses the literal `"AXTrustedCheckOptionPrompt"` instead of the
  non-concurrency-safe imported global.

**Core correctness**
- Rewrote enumeration to walk **every running app's `kAXExtrasMenuBarAttribute`**
  (the actual right-side status items, incl. Control Center) instead of the focused
  app's application menu, which was the wrong element entirely.
- Visibility logic extracted into a pure, unit-tested `MenuBarGeometry` helper.
- Icons fall back to the owning app's icon; titles fall back to description/app name.

**Structure, UX, packaging**
- Split into a testable `MacOverflowCore` library + a thin executable target.
- Menu now rebuilds via `NSMenuDelegate` (idiomatic) instead of the assign/click/nil
  hack; the app no longer **quits** when Accessibility is denied — it shows a "grant
  permission" entry and re-checks on each open.
- Replaced the placeholder test (and stray `BartenderLiteTests.swift`) with real
  `MenuBarGeometry` tests.
- Fixed `make app` to copy from the correct universal-build path and made the
  Info.plist script executable / invoked via `bash`.

**Still needs on-device verification:** whether Accessibility actually surfaces
*overflowed* items on macOS 26 is a runtime question this analysis can't settle. The
enumeration now targets the correct API surface, but items merely clipped under the
notch (vs. pushed fully off-screen) may still require window-server APIs — the
approach the heavier Ice/menustow app takes.

---

## Update (2026-07-12): on-device tuning (MacBook Pro M4, macOS 26)

Verified on a notched MacBook Pro by dumping live Accessibility data (a debug mode
that writes `/tmp/macoverflow-ax.log` when the `AXDebug` default is set). This
resolved the "does it actually work" question above and drove several fixes.

**How macOS 26 actually hides menu bar items (reverse-engineered):**
- **Control Center owns most items** and vends ~10 **empty placeholder slots**
  (`AXEnabled=0`, size 0×0) — now skipped.
- **Names** come from `AXDescription` / `AXHelp` / `AXIdentifier` (title is usually
  empty), falling back to the owning app name.
- Overflowed items keep **normal-looking on-bar coordinates** — macOS just doesn't
  draw them. So visibility can't be judged from "is X on screen" alone. Items are
  hidden by being: parked off-screen (odd X/Y), **painted over by the frontmost
  app's menus** on the left, or **on the wrong side of the notch**.

**Detection now models all three (public APIs only):**
- Menu bar band check (X on a screen, top edge near `y≈0`).
- **App-menu occlusion** — measures the frontmost app's menu width
  (`kAXMenuBarAttribute`); items whose center is left of it are hidden.
- **Notch** — reads the notch span via `NSScreen.auxiliaryTopLeftArea/…RightArea`;
  on a notched display, items that don't clear the notch's right edge (plus a small
  guard band, since macOS won't render flush against the notch) are hidden. This is
  the case that catches ClipboardHistory et al. at low resolution.

**Other fixes/features this round:**
- **Concurrent scan** (`DispatchQueue.concurrentPerform`) — the initial cold scan was
  slow because it queried every app's AX serially; now fanned out across cores.
- **Freeze fix (critical):** the scan runs off the main thread with a 0.25s per-call
  AX timeout, so it can never block the menu's input-grabbing run loop (an earlier
  version froze the keyboard system-wide).
- **Stable code signing** — `make app` signs with a Developer identity so the
  Accessibility grant persists across rebuilds (ad-hoc signing changes identity every
  build, which made macOS re-prompt endlessly).
- **"All Menu Bar Items" window** — lists every extra (hidden + visible) with icon,
  name, and owner; **rows are clickable** to activate any item. This is also the
  practical answer to boundary imperfection: anything is reachable regardless of
  bucket.
- **Stale-entry pruning + Rescan** — items whose owning process has quit are dropped
  immediately; a Rescan command and refresh-after-click keep the list current.

**Remaining honest limitations:**
- **Clicking is best-effort.** `performClick` tries press → show-menu → child; items
  whose apps only respond to a real mouse-down at an on-screen location can't be
  triggered while off-screen. Full reliability needs synthetic mouse events (the
  Ice/menustow window-server approach).
- **"App-hidden" vs "overflowed" are indistinguishable** — an app that parks its own
  icon off-screen (e.g. Copilot, JetBrains Toolbox with their menu bar icon turned
  off) looks identical to an overflowed item, so both appear in the hidden list.
- **Multi-display** notch/menu-bar handling assumes the primary notched display;
  secondary-display menu bars may be misclassified.


