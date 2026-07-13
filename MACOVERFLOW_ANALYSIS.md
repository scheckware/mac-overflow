# Mac Overflow — Security, Efficiency & Architecture Analysis

_Last updated: 2026-07-12. Reflects the code as it currently stands (post-fork
work). Reviewed: full `Sources/` + `Tests/` (~790 lines of source across 6 Swift
files, 116 lines of tests), `Package.swift`, `Makefile`, `scripts/`,
`release-workflow.yml`, `Casks/`. A dated change-history is at the end._

## TL;DR

- **What it is:** a minimal, dependency-free macOS menu bar **overflow viewer** —
  a ≡ icon that lists menu bar status items macOS has hidden (overflowed) and lets
  you activate them. Version **1.0 (build 6)**, MIT-licensed (fork of
  `omniaura/mac-overflow`), bundle id `com.omniaura.mac-overflow`.
- **Security:** **very good.** No network, no shell/exec, no dynamic code, no
  private APIs, no bundled binaries, **zero dependencies**. Requests only the
  **Accessibility** permission and uses it narrowly (menu-bar-extra metadata only);
  keeps nothing, sends nothing. The one broad power (Accessibility) is inherent to
  the app class and used minimally.
- **Efficiency:** **good.** The Accessibility scan runs **off the main thread**,
  **concurrently across cores**, with a **0.25 s per-call timeout** — so it can't
  freeze input and bounds the cost of any unresponsive app. One scan per menu open.
- **Approach:** **sound and honest.** Visibility is decided by a pure, unit-tested
  geometry model grounded in real on-device data (menu-bar band + app-menu
  occlusion + notch). It squarely acknowledges the public-API ceiling: activating
  some items and distinguishing "app-hidden" from "overflowed" aren't fully solvable
  without the private-API approach Ice/Bartender take.
- **Maturity:** now a **working, signed, tested utility** (17 passing tests, clean
  Swift 6 build) — a large step up from the non-compiling prototype it started as.

---

## What it is

Mac Overflow is a menu bar **agent** (`.accessory`, no Dock icon). It shows a single
≡ status item; opening it lists the status items ("menu bar extras") that aren't
currently visible, each clickable to activate the real item. A separate **All Menu
Bar Items** window lists every extra (hidden and visible).

| | |
|---|---|
| **Language / UI** | Swift 6 (strict concurrency), AppKit entry point + SwiftUI for the All Items window |
| **Build** | Swift Package Manager (`swift-tools-version: 6.0`), **zero dependencies** |
| **Targets** | `MacOverflowCore` (testable library) + `MacOverflow` (thin executable) + tests |
| **Min OS** | macOS 13 (Ventura); developed/verified on macOS 26 |
| **Distribution** | GitHub Releases (DMG/zip) + Homebrew cask; semantic-release CI |
| **Permissions** | Accessibility only |
| **License** | MIT (LICENSE present + bundled in the `.app`) |

## Architecture (how it works now)

Clean split between a pure, testable core and a thin UI shell:

| File (lines) | Role |
|---|---|
| `Sources/MacOverflowCore/AX.swift` (62) | Failure-tolerant wrappers over the C Accessibility API (`attribute`, `point`, `size`, `bool`, `children`, `perform`). |
| `Sources/MacOverflowCore/MenuBarItem.swift` (110) | Value type for one extra (title/owner/pid/icon/frame/`isVisibleInBar` + `AXUIElement`). `from(...)` factory resolves a display name; `performClick()` forwards a press. |
| `Sources/MacOverflowCore/MenuBarGeometry.swift` (87) | **Pure** visibility model: `MenuBarLayout` snapshot + `isVisible(itemFrame:layout:)`. No AppKit/AX → unit-testable. |
| `Sources/MacOverflowCore/MenuBarMonitor.swift` (186) | `@MainActor ObservableObject`. Captures a Sendable snapshot on main, runs the AX scan off-main + concurrently, publishes `allItems` / `hiddenItems`. |
| `Sources/MacOverflow/main.swift` (265) | AppKit entry point + `AppDelegate` (`NSMenuDelegate`): status item, ≡ menu, About/License, self-hidden handling, All Items window. |
| `Sources/MacOverflow/AllItemsView.swift` (82) | SwiftUI list (Hidden / In Menu Bar), clickable rows, hosted via `NSHostingController`. |

**Scan flow (`MenuBarMonitor.refresh`)**
1. On the main actor, snapshot everything the scan needs as **Sendable** data:
   screen frames, menu-bar thickness, notch geometry (`NSScreen.auxiliaryTop*Area`),
   frontmost PID, and `(pid, name, icon)` per running app.
2. Off-main (`scanQueue.async` → `DispatchQueue.concurrentPerform`): for each app,
   `AXUIElementCreateApplication` → read `kAXExtrasMenuBarAttribute` → children;
   skip disabled/zero-size placeholders; build a `MenuBarItem`; compute
   `isVisibleInBar` via `MenuBarGeometry`. Every AX element gets a **0.25 s**
   messaging timeout.
3. Results marshalled back to the main actor (`Task { @MainActor }`), stored in
   `@Published allItems`; `onUpdate` fires for the imperative `NSMenu`.

**UI flow (`AppDelegate`)** — the ≡ menu rebuilds via `NSMenuDelegate`: each open
triggers a fresh scan and shows **"Scanning…"** until it lands (so no stale data and
no shrink-under-cursor). Clicking an item calls `performClick()`; clicking the
**Mac Overflow** row shows our own menu via AppKit (never AX). ~3 s after launch a
one-shot scan checks whether our own ≡ is overflowed and, if so, opens All Items.

## Security analysis

**Findings — clean across the board:**

| Vector | Result |
|---|---|
| Network | **None.** No `URLSession`/sockets/telemetry. Only `NSWorkspace.open` on a `x-apple.systempreferences:` deep link, the bundled `LICENSE.txt`, and a fallback GitHub URL — all user-initiated, benign. |
| Code execution / dynamic loading | **None.** No `Process`/`NSTask`/`osascript`/`dlopen`/`eval`/base64. |
| Private APIs | **None.** Public `ApplicationServices` (AX) + `NSScreen.auxiliaryTop*Area` (public since macOS 12) + AppKit. |
| Dependencies | **Zero** — no third-party supply chain. |
| Bundled binaries | **None** — source only. |
| Persistence / data at rest | **None** in normal operation. Scanned metadata is held only in memory; the old `/tmp` debug log is gone. |
| Entitlements / sandbox / hardened runtime | No entitlements file; not sandboxed (can't be, given AX). No hardened runtime — see distribution note. |

**Privilege posture.** Accessibility is a broad grant, but this app exercises it
narrowly: it reads menu-bar-extra **metadata** (title, description, frame, icon,
enabled) and posts `AXPress` to activate items. It does not read window contents,
monitor keystrokes, or request Input Monitoring / Post Events / Screen Recording.
Nothing scanned leaves the process.

**Resilience note.** A previously-found bug — AX-pressing the app's *own* status item
deadlocks the main thread — is now hard-guarded in `performClick()`
(`ownerPID != getpid()` → early return before any AX call). Good defensive posture.

**Force-unwrap review.** The `as!` casts are safe: `value as! AXValue` is guarded by a
`CFGetTypeID` check; `image.copy() as! NSImage` is contractually an `NSImage`.
`statusItem` is an implicitly-unwrapped optional set in `applicationDidFinishLaunching`
before any use. No trap risk observed.

**Remaining nits (not vulnerabilities):**
- `Casks/mac-overflow.rb` uses `sha256 :no_check` — the Homebrew cask doesn't pin the
  download hash. Fine while pre-release; pin it once artifacts are stable. Building
  from source avoids it.
- Signing is **Apple Development** (a development cert), and CI does **not** notarize.
  Fine for personal use; distributing to others cleanly (no Gatekeeper warning) needs
  **Developer ID + notarization**.

## Efficiency analysis

**Strengths:**
- **Off-main + concurrent.** The scan runs on a background queue and fans out across
  cores with `concurrentPerform`, so per-app AX IPC (and its one-time connection
  setup) overlaps instead of serializing. This is also what keeps the UI responsive.
- **Bounded blocking.** `AXUIElementSetMessagingTimeout(…, 0.25)` on every element
  caps how long any single unresponsive app can stall the scan.
- **No redundant scans.** `refresh()` early-returns if a scan is already in flight or
  the app isn't trusted, so overlapping triggers (menu open + refresh-after-click)
  collapse to one.
- **Cheap UI.** Menu build reads cached results (no AX on the menu-tracking loop);
  stale entries are pruned with a cheap `NSRunningApplication(processIdentifier:)`
  check; icons are resized via a small copy.

**Costs / trade-offs (all acceptable):**
- **Every menu open scans every running app.** There's no cache of "which apps have
  extras," so a machine with ~150 processes does ~150 `AXUIElementCreateApplication`
  + attribute reads per open. Parallelism + the 0.25 s cap keep this sub-second in
  practice, and freshness is the correct default for a menu, but it is repeated work.
  A future optimization could remember PIDs that returned extras and re-scan only
  those plus newly-launched apps.
- **AX thread-safety** across `concurrentPerform` is relied upon empirically (each
  iteration targets a distinct app's elements). Not formally documented by Apple, but
  standard practice and safe here since results are collected under a lock.

## Approach & correctness

The core question — "is a status item visible or overflowed?" — is handled well.
`MenuBarGeometry.isVisible` decides visibility from three occlusion models, all via
**public** APIs and derived from real on-device Accessibility captures:
1. **Menu-bar band** — item top edge near `y ≈ 0`, horizontal center within a screen.
2. **App-menu occlusion (non-notched)** — items whose center is left of the frontmost
   app's menu width are painted over.
3. **Notch (notched displays)** — the notch is the authoritative left boundary;
   items must clear its right edge by a guard band. Deliberately **ignores** the
   app-menu width here so results don't depend on which app is frontmost (that
   inconsistency previously made the ≡ menu and All Items disagree).

Extracting this into a pure, dependency-free type with **17 unit tests** (including
regression cases from real coordinates) is the right design — the fiddly logic is
testable without a live window server or granted permissions.

**Honest, documented limitations** (inherent to a public-API app):
- **Activation is best-effort.** `performClick()` tries press → show-menu → child
  press. Some items advertise `AXPress` yet ignore it when off-screen; there's no
  reliable public signal for "clicked but nothing happened." Full reliability needs
  synthesized mouse events at the item's on-screen location (private-API territory).
- **"App-hidden" vs "overflowed" are indistinguishable** — an app that parks its own
  icon off-screen looks identical to a genuinely overflowed one, so both appear as
  hidden.
- **Multi-display / notch guard.** The notch rule assumes the primary notched
  display; secondary menu bars may be misclassified. The `notchGuard = 24` px is a
  tuned heuristic (macOS leaves a gap so items don't render flush against the notch),
  not a value read from the system.

## Code quality

- **Concurrency:** clean Swift 6 strict-concurrency model — `@MainActor` UI/monitor,
  a Sendable snapshot handed to a `nonisolated` scan, results marshalled back via
  `Task { @MainActor }`. `MenuBarItem` is `@unchecked Sendable` (immutable, holds CF
  types) with a clear rationale.
- **Separation:** pure core vs. UI shell; the AX layer is small and uniformly
  failure-tolerant.
- **Test coverage gap:** only the pure geometry is unit-tested. The monitor, AX
  helpers, and menu logic are effectively integration code (need a live system +
  granted permission), so they're validated by manual run, not tests. Reasonable, but
  it's the main coverage gap.

## macOS 26 compatibility

Runs and works on macOS 26 (verified on a notched MacBook Pro M4). All APIs are
public and current; the detection is specifically adapted to macOS 26's model where
Control Center owns most menu-bar extras (including empty placeholder slots, which are
filtered out). No deprecated or version-fragile calls. The macOS-13 floor is a floor,
not a ceiling.

## Suggested improvements (prioritized)

**Distribution (do these before sharing with others)**
1. **Developer ID signing + notarization** so it opens without Gatekeeper warnings on
   other Macs (CI currently builds/publishes but doesn't notarize).
2. **Pin the Homebrew cask hash** (drop `sha256 :no_check`) once release artifacts
   are stable.

**Robustness / quality**
3. **Broaden tests** beyond geometry — e.g. factor the placeholder-skip and
   name-resolution logic so they can be exercised with synthetic AX-like inputs.
4. **Scan efficiency (optional)** — cache PIDs known to vend extras and re-scan only
   those + newly-launched apps, to cut the per-open work on busy machines.
5. **Custom app icon** — currently an SF Symbol only; a real `.icns`/asset would
   improve Finder/Dock presentation (minor, cosmetic).

**Nice-to-have**
6. **Persist the ≡ position** with `NSStatusItem.autosaveName` so the user's chosen
   spot survives relaunches (the closest public-API approximation of "keep it left of
   the hidden cluster").

---

### Verdict

A safe, efficient, honestly-scoped menu bar utility. It does one thing with public
APIs, minimal privilege, zero dependencies, and no network — and it's now correct and
tested where it counts. Its ceiling (fully reliable activation, forcing icon
placement) is set by Apple's public API surface, and the code is candid about that
rather than reaching for fragile private-API workarounds. For personal/small-group
use it's solid today; for public distribution, add Developer ID signing +
notarization.

---

## Change history (condensed)

**2026-07-11 — initial review & repair.** As downloaded, the project **did not
compile** (`kAXImageAttribute` doesn't exist; Swift 6 concurrency errors). Fixed the
build; split into `MacOverflowCore` + executable; rewrote enumeration to walk every
app's `kAXExtrasMenuBarAttribute` (was reading the focused app's *application* menu —
the wrong element); added real geometry tests; made the app non-fatal when
Accessibility is denied.

**2026-07-12 — on-device tuning (macOS 26, notched MBP).** Using a temporary
`AXDebug` capture, reverse-engineered how macOS 26 hides extras (Control Center
ownership, empty placeholders, off-screen parking, app-menu and notch occlusion) and
built the three-model visibility logic. Fixed a **system-wide input freeze** (moved
the scan off-main with a per-call timeout), parallelized the scan, added stable code
signing (Accessibility grant now persists across rebuilds), the **All Menu Bar
Items** window, Rescan, and stale-entry pruning.

**2026-07-12 — later same day.** Removed unreliable "(Not Clickable)" detection
(advertised AX actions don't predict clickability) and the click beep; hard-guarded
the **self-AX-press deadlock**; menu now shows "Scanning…" then this open's fresh
results (no stale/shrink); dropped the empty "Mac Overflow Settings" window (switched
to a pure AppKit entry point); set version **1.0 (build N)** via
`scripts/generate-info-plist.sh` (marketing vs build number) surfaced in the About
panel and Finder; added a **bump-build** skill; added the **MIT `LICENSE`**
(preserving upstream copyright), bundled it in the `.app`, and surfaced upstream
attribution + a "View License…" button in the About panel.
