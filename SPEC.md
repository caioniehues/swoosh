# Swoosh — SPEC

Open-source macOS window snapping via trackpad gestures on titlebars. A faithful, free, MIT-licensed clone of the snap subset of [Swish](https://highlyopinionated.co/swish/).

> Status: pre-implementation. Spec only. No code beyond stubs yet.

---

## 1. Goal

Replicate Swish's titlebar-snap behavior: a two-finger swipe on any window's titlebar instantly snaps that window to a half / quarter / third of the screen. The same actions are invokable via keyboard shortcuts.

The differentiating UX detail is **localized invocation** — the gesture only fires when the cursor is over a window's titlebar, so normal two-finger scrolling everywhere else works unchanged.

## 2. Non-goals (v1)

- Dock gestures, menubar gestures (deferred to v2).
- Multi-monitor or Spaces gestures (would require a SIP-off scripting addition à la yabai; out of scope).
- Tiling mode, user-scriptable gestures.
- Mac App Store distribution (impossible — sandbox forbids both AX writes and `MultitouchSupport.framework` access).
- Magic Mouse support (v2 — Swish supports it via double-tap + modifier; not core).
- Localization (English only in v1).

## 3. Differentiator

A faithful, auditable, free implementation. The pitch is for users who can't or won't pay $16, who don't trust closed-source utilities with Accessibility permission, or who want to fork and extend.

No novel features in v1 — match Swish's snap UX so reviewers can compare like-for-like. Differentiation is by **implementation transparency**, not feature set.

## 4. Gesture catalog (v1)

The full set of recognized inputs and their actions. Cursor must be over a window titlebar for trackpad gestures to fire.

### 4.1 Two-finger swipe on titlebar

| Gesture | Action |
|---|---|
| Swipe ← | Snap window to left half |
| Swipe → | Snap window to right half |
| Swipe ↑ | Snap window to top half (or full-screen if already on top half — Swish behavior) |
| Swipe ↓ | Snap window to bottom half (or restore to previous frame if already snapped) |
| Swipe ↖ ↗ ↙ ↘ (diagonal) | Snap to quarter (TL / TR / BL / BR) |

### 4.2 Two-finger hold + position on titlebar (3×3 grid)

While holding two fingers on the titlebar, the area under the cursor highlights the destination cell of a 3×3 grid overlaid on the screen. Release fingers to commit the snap. Swipe outward to cancel.

### 4.3 Keyboard shortcuts

Defaults shown. All configurable from Settings. Modifier prefix: `⌃⌥` (Control + Option), Swish-compatible.

| Key (Arrows) | Key (WASD) | Action |
|---|---|---|
| ← | A | Left half |
| → | D | Right half |
| ↑ | W | Top half / fullscreen |
| ↓ | S | Bottom half / restore |
| ⌃⌥1..9 | — | 3×3 grid cells (1=BL, 9=TR — numpad layout) |
| ⌃⌥0 | — | Full screen |
| ⌃⌥⏎ | — | Restore previous frame |

### 4.4 Multi-window resize

When two windows are snapped sharing an edge, dragging the gap between them (anywhere along the shared edge) resizes both windows simultaneously.

## 5. Architecture

Four layers, each with a single responsibility. Events flow downward; no upward calls.

```
                    ┌────────────────────────────────┐
                    │   CGEventTap (session-level)   │   Layer 1: Capture
                    │  observes kCGEventScrollWheel  │
                    └────────────┬───────────────────┘
                                 │ raw scroll event
                                 ▼
              ┌─────────────────────────────────────────┐
              │  MultitouchSupport.framework (private)  │   Layer 2: Disambiguate
              │  via MTRegisterContactFrameCallback     │
              │  → confirm: exactly 2 fingers down?     │
              └────────────┬────────────────────────────┘
                           │ yes / no
                           ▼
        ┌───────────────────────────────────────────────┐
        │  AX hit-test at cursor location               │   Layer 3: Locate
        │  AXUIElementCopyElementAtPosition             │
        │  walk to kAXWindowRole                        │
        │  cursor.y within window's titlebar band?      │
        └────────────┬──────────────────────────────────┘
                     │ window-ref + direction + magnitude
                     ▼
              ┌───────────────────────────────┐
              │  Snap engine                  │   Layer 4: Act
              │  - resolve target frame       │
              │  - AXUIElementSetAttribute    │
              │    (kAXPosition / kAXSize)    │
              │  - consume original event     │
              └───────────────────────────────┘
```

### 5.1 Threading model

| Layer | Thread / queue | Why |
|---|---|---|
| CGEventTap callback | Tap's runloop on a dedicated background thread | Apple requires tap callbacks to return fast (<70 ms) or the tap is disabled |
| Multitouch callback | The framework's own callback thread | Cannot block; reads only the current finger count, atomic |
| AX hit-test | Serial queue `swoosh.ax` | AX calls are blocking IPC; must not be on event-tap thread |
| Window placement | Same `swoosh.ax` queue | Serializes writes to avoid races |
| Settings UI | `@MainActor` | SwiftUI requirement |

The event tap callback's only synchronous work is checking the finger-count atomic and (if it matches) enqueuing the hit-test onto `swoosh.ax`. Suppression of the original event is decided synchronously by an opt-in flag set by the finger-count check — the AX work happens after the event has already been swallowed.

### 5.2 Suppression strategy

The hardest part. Two-finger pan on a titlebar must be swallowed without breaking normal scrolling on the same titlebar (e.g. some apps put a scroll view in a custom titlebar).

Approach: only consume the event if **all three** are true:
1. Exactly 2 active contacts.
2. Event's `kCGScrollWheelEventScrollPhase` is `kCGScrollPhaseBegan` or `kCGScrollPhaseChanged`.
3. AX hit-test returns a window whose subrole is `kAXStandardWindowSubrole` and the cursor y is within `[kAXFrame.minY, kAXFrame.minY + 28pt]` (titlebar band).

If any fails, return the event unchanged. The 28pt titlebar height is the standard macOS metric; tall titlebars (Safari) are detected by reading `kAXTitleBarHeightAttribute` when available.

## 6. Permission flow

```
First launch
  ├── Show onboarding window
  ├── Explain why Accessibility is needed (titlebar hit-test + window move)
  ├── Open System Settings > Privacy & Security > Accessibility
  ├── Poll AXIsProcessTrustedWithOptions every 1s
  └── On grant → close onboarding, start event tap

If Sequoia (15+) native window tiling is detected enabled
  └── One-time alert: "macOS tiling will fight Swoosh's snaps. Disable it?"
      → Settings > Desktop & Dock > Windows > "Drag windows to screen edges to tile" = off
      → User dismissable with "I know what I'm doing"
```

`MultitouchSupport.framework` does **not** require Input Monitoring permission as of macOS 14 — it's a private SPI that talks directly to IOHID. This may change; specced as a v1 risk.

## 7. Key types (Swift API sketch)

Sketches only, not final signatures. Establishes the layer boundaries.

```swift
// Layer 1
final class EventTap {
    init(onScroll: @escaping (CGEvent) -> CGEvent?)
    func enable() throws
    func disable()
}

// Layer 2
final class MultitouchClient {
    var fingerCount: Int { get }   // atomic
    func start() throws
    func stop()
}

// Layer 3
struct WindowHit {
    let window: AXUIElement
    let pid: pid_t
    let frame: CGRect            // window frame in global coords
    let titlebarHeight: CGFloat
}
enum HitTest {
    static func windowUnderCursor(at point: CGPoint) -> WindowHit?
    static func isOverTitlebar(_ hit: WindowHit, cursor: CGPoint) -> Bool
}

// Layer 4
enum SnapTarget {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case leftThird, centerThird, rightThird
    case fullScreen, restore
    case gridCell(row: Int, col: Int, rows: Int, cols: Int)
}
enum SnapEngine {
    static func frame(for target: SnapTarget, on screen: NSScreen) -> CGRect
    static func apply(_ target: SnapTarget, to window: AXUIElement) throws
}

enum Direction {
    case left, right, up, down
    case upLeft, upRight, downLeft, downRight
    init?(scrollDelta: CGVector)   // resolves dominant axis + diagonal threshold
}
```

## 8. Edge cases & known issues

- **Stage Manager**: re-tiles windows after AX placement; not officially supported in v1.
- **macOS 15 Sequoia native tiling**: animations conflict with our placement. Onboarding prompts the user to disable.
- **Fullscreen Spaces**: AX placement on a fullscreen window has no useful meaning; gesture is no-op when window is fullscreen.
- **Per-display scaling / Retina**: AX uses points, but `NSScreen.frame` origin differs per display. Always compute target frame relative to the *screen containing the window's current center*, not the main screen.
- **Custom titlebars (Electron, Safari)**: titlebar height varies. Read `kAXTitleBarHeightAttribute`; fall back to 28pt if absent.
- **Windows refusing AX writes**: some apps (older Java, certain Electron builds) ignore `kAXPositionAttribute`. Log + no-op.
- **Discontiguous screen layouts**: when displays don't share an edge, "snap to next display" semantics are out of scope (v2).
- **Pinned-to-all-desktops windows**: may behave unexpectedly with Spaces; not addressed in v1.

## 9. Testing strategy

| Layer | Test type | Notes |
|---|---|---|
| Layer 1 (EventTap) | Manual + smoke | Can't unit-test a real CGEventTap |
| Layer 2 (Multitouch) | Manual | Private API; mock the count for downstream tests |
| Layer 3 (HitTest) | Unit | `isOverTitlebar` is pure math on a `CGRect`; testable in isolation |
| Layer 4 (Snap math) | Unit | `SnapEngine.frame(for:on:)` is pure; full coverage of every `SnapTarget` × screen-size combo |
| Direction resolver | Unit | `Direction(scrollDelta:)` is pure |
| Integration | Manual matrix | See §11 |

Manual test matrix lives in `docs/manual-test-matrix.md` (created when implementation starts).

## 10. Plan B for `MultitouchSupport`

If Apple removes or breaks `MultitouchSupport.framework`:

1. Wrap each captured `kCGEventScrollWheel` as `NSEvent.event(with:)`.
2. Inspect `event.subtype` — `.touch` indicates trackpad pan (vs. mouse wheel which is `.gestureBegan`/`.gestureEnded` empty).
3. Inspect `event.momentumPhase` and `event.phase` — trackpad pan has `.began` / `.changed` / `.ended`; mouse wheel does not.
4. Accept some false negatives (Magic Mouse single-finger scroll looks similar enough that we can't perfectly distinguish; document the limitation).

Plan B is specced but not implemented unless triggered.

## 11. Technical decisions

| Concern | Decision | Rationale |
|---|---|---|
| Language | Swift 5.10+ | Native, AX/CG/SwiftUI integration |
| UI framework | SwiftUI + `MenuBarExtra` | Less code for settings; AppKit only for taps |
| macOS target | 14.0 Sonoma+ | Modern SwiftUI, ~90% of active users, less legacy code |
| License | MIT | Permissive; matches Rectangle, Amethyst, AeroSpace |
| Build | Swift Package Manager (executable target) + shell script to bundle `.app` | Avoids Xcode-project XML; works headless in CI |
| IDE | Open `Package.swift` in Xcode | No checked-in `.xcodeproj` |
| Updates | None in v0.x (manual GitHub Releases). | Personal project framing |
| Distribution | Unsigned zipped `.app`. | $99/yr Developer Program deferred |
| CI | GitHub Actions: `swift build` + `swift test` + bundle on tag | No notarization step yet |
| Testing | `swift-testing` (Swift 6) for unit tests | Modern; better ergonomics than XCTest |

## 12. De-risk plan (week 1 — must pass before any UI is written)

Ship a ~200-line menubar-only spike (`swoosh-spike` executable) that:

1. Requests Accessibility permission and waits for grant via polling.
2. Installs a `CGEventTap` listening to `kCGEventScrollWheel` at `.cgSessionEventTap`.
3. Subscribes to `MTDeviceCreateDefault` contact-frame callbacks; maintains an atomic finger count.
4. On a scroll event where `fingerCount == 2`: calls `AXUIElementCopyElementAtPosition`, walks up to `kAXWindowRole`, checks whether cursor.y is within the titlebar band of the window's `kAXFrame`.
5. If yes: `os_log` `{pid, title, direction, suppressed: true}` and returns `nil` from the tap callback to consume the event.
6. If no: returns the event unchanged.

**Success criteria** (all three must hold):
- Two-finger swipe on a titlebar logs the direction and does NOT scroll the underlying view.
- Two-finger scroll on Safari content, Finder, VS Code editor — scrolls normally.
- Single-finger drag on a titlebar — still moves the window normally.

If any of these fails, the project pivots before any UI work happens.

## 13. Project layout

```
swoosh/
├── SPEC.md
├── README.md
├── LICENSE                                (MIT)
├── .gitignore
├── Package.swift                          (SPM, executable target)
├── Sources/
│   ├── Swoosh/                            (the app)
│   │   ├── App.swift                      (@main, MenuBarExtra)
│   │   ├── Gestures/
│   │   │   ├── EventTap.swift             (CGEventTap wrapper)
│   │   │   ├── MultitouchClient.swift     (private-API bridge)
│   │   │   ├── MultitouchSupport.h        (private API headers)
│   │   │   └── GestureRecognizer.swift    (composes layers 1+2)
│   │   ├── Windows/
│   │   │   ├── AXBridge.swift             (Accessibility wrappers)
│   │   │   ├── WindowHitTest.swift        (cursor → window + titlebar test)
│   │   │   └── WindowMover.swift          (apply target frame)
│   │   ├── Snap/
│   │   │   ├── Direction.swift            (scroll delta → cardinal/diagonal)
│   │   │   ├── Grid.swift                 (2x2, 3x2, 3x3 math)
│   │   │   └── SnapEngine.swift           (SnapTarget → CGRect)
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift
│   │   │   └── Preferences.swift          (@AppStorage)
│   │   └── Onboarding/
│   │       └── PermissionsView.swift
│   └── SwooshSpike/                       (week-1 de-risk binary)
│       └── main.swift
├── Tests/
│   └── SwooshTests/
│       ├── GridTests.swift
│       ├── DirectionTests.swift
│       └── SnapEngineTests.swift
├── Resources/
│   └── Info.plist                         (LSUIElement=YES, AX usage description)
├── Scripts/
│   └── bundle.sh                          (wrap binary into .app)
├── docs/
│   └── manual-test-matrix.md              (added when impl starts)
└── .github/
    └── workflows/
        └── ci.yml                         (build + test on push, bundle on tag)
```

## 14. Milestones

| Week | Deliverable | Exit criteria |
|---|---|---|
| 1 | Spike passes (§12) | All three success-criteria bullets hold on macOS 14 + 15 + 26 |
| 2 | Snap engine | Halves/quarters/thirds via AX, unit tests green |
| 3 | Keyboard shortcuts + multi-window resize | Default bindings functional |
| 4 | Settings UI + onboarding + Sequoia tiling detection | First-launch flow works end-to-end |
| 5 | GitHub Actions: build + test + bundle-on-tag (unsigned) | `git tag v0.1.0` produces a downloadable zip |
| later | Signing, notarization, Sparkle, Homebrew Cask | Only if there's an audience |

## 15. Project framing

This is a personal open-source project, not a product. That collapses several decisions:

- **Distribution v0.x**: unsigned `.app` zipped on GitHub Releases. README documents `xattr -dr com.apple.quarantine` for users.
- **Updates v0.x**: skip Sparkle. Users grab new releases manually.
- **Telemetry**: none, ever.
- **Support**: best-effort via GitHub issues. No SLA.

Sparkle / signing / notarization / Homebrew Cask sit in a "v1.0 — if anyone else cares" milestone.

## 16. Prior art and references

- [Swish](https://highlyopinionated.co/swish/) — the original, closed-source, $16
- [Rectangle](https://github.com/rxhanson/Rectangle) — MIT, keyboard snapping only
- [Loop](https://github.com/MrKai77/Loop) — GPL-3, radial-menu invocation
- [yabai](https://github.com/koekeishiya/yabai) — MIT, tiling, SIP-disabled features
- [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) — GPL-3, references for private MultitouchSupport usage
- [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) — open Swift wrapper for the private framework
- [usagimaru/EventTapper](https://github.com/usagimaru/EventTapper) — CGEventTap reference
- Ryan Hanson, [Touching Apple's private MultitouchSupport framework](https://medium.com/ryan-hanson/touching-apples-private-multitouch-framework-64f87611cfc9)
- Apple, [AXUIElement Reference](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- Apple, [Quartz Event Services](https://developer.apple.com/documentation/coregraphics/quartz_event_services)

## 17. Open questions

- Name "Swoosh" kept for now (personal project; revisit if it ships publicly).
- Whether to expose Plan B (NSEvent-only) as a user toggle for users who don't want a private-API dependency.
