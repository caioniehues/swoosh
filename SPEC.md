# Swoosh — SPEC

> The canonical technical design. Strategy and the resolved product forks live in [`STRATEGY.md`](./STRATEGY.md); the de-risk spike and fixture harness in [`DERISK.md`](./DERISK.md); sequencing in [`ROADMAP.md`](./ROADMAP.md).
>
> **Status: pre-implementation. Spec only.** No code beyond stubs yet. Last updated 2026-05-30.

Open-source macOS window snapping and resizing via two-finger trackpad gestures on titlebars. A faithful, free, MIT-licensed reimplementation of the snap subset of [Swish](https://highlyopinionated.co/swish/) — matching its *feel*, beating its 3×3 size ceiling.

---

## 1. Goal

Replicate the three things Swish users actually love, in this priority order:

1. **Titlebar two-finger swipe → snap** to a half / quarter / third (or any fraction) of the screen. The gesture only fires when the cursor is over a window's titlebar, so normal two-finger scrolling everywhere else is untouched (**localized invocation** — the core UX detail).
2. **Divider-drag multi-window resize** — when two windows share a snapped edge, dragging the gap resizes both at once. This is Swish's single most-cited *unique* feature; it is a headline, not plumbing.
3. **Haptic threshold feedback** — a "ready" tap when a gesture crosses its commit threshold and a "done" tap on commit, so snapping *feels* native and physical.

Beyond parity, the one capability we add on day one: **arbitrary fractional/pixel sizes** (e.g. ultrawide 4- and 5-column layouts), which Swish caps at 3×3 and defers to an unshipped "Swish 2."

All actions are also invokable via keyboard shortcuts.

## 2. Non-goals (v1)

- Dock gestures, menubar gestures, App-Switcher gestures (deferred to v2).
- Multi-monitor *gestures* (placement across displays works; cross-display *gestures* are v2) and Spaces gestures (would require a SIP-off scripting addition à la yabai; out of scope).
- A scripting platform, control socket, or user-bindable arbitrary actions — an explicit strategic non-goal (`STRATEGY.md §4.2`). The engine is config-*driven* internally but exposes no user scripting surface in v1.
- Mac App Store distribution (sandbox forbids both AX writes and `MultitouchSupport` access — structurally impossible).
- Magic Mouse support (v2; Swish supports it via double-tap + modifier — not core).
- Localization (English only in v1).

## 3. Differentiator

A faithful, auditable, free implementation. The pitch is for users who can't or won't pay $16, who won't grant Accessibility to a closed binary, or who want to fork and extend. v1 matches Swish's snap UX so reviewers can compare like-for-like; differentiation is by **implementation transparency** and the **fraction-native engine**, not a sprawling feature set. See `STRATEGY.md §2` for why this survives Apple's free native tiling.

## 4. Gesture catalog (v1)

Cursor must be over a window titlebar for trackpad gestures to fire.

### 4.1 Two-finger swipe on titlebar

| Gesture | Action |
|---|---|
| Swipe ← / → | Snap to left / right half |
| Swipe ↑ | Snap to top half — or full-screen if already on top half (Swish behavior) |
| Swipe ↓ | Snap to bottom half — or restore previous frame if already snapped |
| Swipe ↖ ↗ ↙ ↘ | Snap to quarter (TL / TR / BL / BR) |

Direction resolves the dominant axis with a diagonal threshold (see `Direction` in §9).

### 4.2 Two-finger hold + position on titlebar (grid picker)

While holding two fingers on the titlebar, the cell under the cursor highlights the destination on a grid overlaid on the screen. Release to commit; swipe outward to cancel. The grid is **3×3 by default but configurable** (e.g. 4×1 or 5×1 for ultrawide) because the engine is fraction-native (§5) — the picker just renders whatever grid the resolved layout defines.

### 4.3 Divider-drag multi-window resize *(headline feature)*

When two windows are snapped sharing an edge, dragging the gap between them — anywhere along the shared edge — resizes both simultaneously.

**Input path (distinct from the swipe pipeline).** Divider-drag is a *mouse/pointer drag*, not a scroll gesture, so it does not flow through the Layer 1 scroll-wheel tap. The event tap additionally observes `kCGEventLeftMouseDown` / `kCGEventLeftMouseDragged` / `kCGEventLeftMouseUp`. On left-mouse-down, a synchronous, non-blocking check (the same fast geometry source as §6.2 — `CGWindowListCopyWindowInfo` / the cached window map, **not** an AX hit-test) decides whether the cursor sits in the narrow band straddling two windows' shared snapped edge. If so, the event is consumed and a resize session begins; otherwise it passes through untouched. This second modality bypasses the titlebar-only §6.2 gate and is reflected in the §6 diagram and the §6.1 threading table.

**Resize session.** Writes both windows' frames in lockstep on the `swoosh.ax` queue. The shared-edge relationship is inferred from current frames, not stored state, so it survives windows being moved by other tools.

### 4.4 Haptic feedback

- **Ready tap** when a swipe crosses its commit threshold or the hold-grid cursor enters a new cell.
- **Done tap** on commit.
- Configurable; off automatically on hardware without a haptic engine. Never fires during a cancelled gesture.

**API path is spike-gated (S4 in `DERISK.md §1`).** The public `NSHapticFeedbackManager` is oriented to foreground AppKit views and the built-in trackpad, and exposes only three fixed patterns. Swoosh actuates from a *background, non-frontmost* utility, often on an *external* Magic Trackpad — an unproven combination. The M0 spike must confirm whether `NSHapticFeedbackManager` works in that context; if it does not, the real path is the private `MTActuator` family (`MTActuatorCreateFromDeviceID` / `MTActuatorOpen` / `MTActuatorActuate`), exported by the same `MultitouchSupport.framework` already loaded for finger-count. **If `MTActuator` is required, it is a fourth private-API surface** and must appear in the capability manifest and every "private-API surface" count (`STRATEGY.md §5`).

### 4.5 Keyboard shortcuts

Defaults shown; all configurable. Modifier prefix `⌃⌥` (Control+Option), Swish-compatible.

| Arrows | WASD | Action |
|---|---|---|
| ← / → | A / D | Left / right half |
| ↑ | W | Top half / fullscreen |
| ↓ | S | Bottom half / restore |
| ⌃⌥1..9 | — | Grid cells (numpad layout: 1 = BL, 9 = TR) |
| ⌃⌥0 | — | Full screen |
| ⌃⌥⏎ | — | Restore previous frame |
| ⌃⌥F | — | Exit native fullscreen |

### 4.6 Exit-fullscreen + restore (first-class verbs)

Two dead-ends Swish leaves open, fixed here:

- **Exit fullscreen** — a gesture and shortcut (`⌃⌥F`) reliably exit a window from native macOS fullscreen. There is **no public** fullscreen attribute or action (the SDK exposes only `kAXFullScreenButtonAttribute`, a button *reference*, plus the `AXPress`/`AXRaise` actions). Two real paths: set the **undocumented private** attribute `"AXFullScreen"` (`CFSTR("AXFullScreen")`) to `false`, or resolve the window's `kAXFullScreenButton` child element and send it `AXPress`. The private-attribute path is preferred for reliability; because `"AXFullScreen"` is private, it counts toward the capability surface (`STRATEGY.md §5`). Replaces the old spec's "fullscreen = no-op" contradiction.
- **Restore** — `Swipe ↓` on an already-snapped window, the keyboard restore (`⌃⌥⏎`), and the post-snap restore all return the window's **previous frame**, backed by a small per-window **ring buffer** (default depth 4) so repeated restore walks back through recent placements. The original pre-snap frame is always the deepest entry.

## 5. Snap engine — fraction/pixel-native

The core abstraction is **not** a fixed enum of named targets. A snap target resolves to a normalized rectangle over the window's screen visible frame; named presets and grids are conveniences that produce one.

```swift
/// A rectangle expressed as fractions (0...1) of a screen's visibleFrame,
/// with optional pixel insets. (0,0) is top-left. Resolve against the
/// visibleFrame of the screen containing the window, then express the result
/// in AX global coordinates (top-left origin, +y down, primary-display
/// referenced) — see §10. NO flip is needed at the AX apply boundary; a flip
/// applies ONLY if an intermediate step uses AppKit/NSScreen (bottom-left)
/// coords, and that flip must use the PRIMARY screen's height.
struct FractionalRect {
    var x, y, w, h: Double          // fractions of visibleFrame
    var inset: NSEdgeInsets = .init() // pixel gaps (outer margins / gutters)
}

enum SnapTarget {
    case fraction(FractionalRect)                    // the native vocabulary
    case preset(Preset)                              // leftHalf, topRightQuarter, centerThird, …
    case gridCell(row: Int, col: Int, rows: Int, cols: Int) // any N×M, incl. ultrawide 5×1
    case fullScreen
    case restore                                     // pops the ring buffer (§4.6)
}
```

- **Presets** (`leftHalf = (0,0,0.5,1)`, `topRightQuarter = (0.5,0,0.5,0.5)`, thirds, etc.) compile to `FractionalRect`.
- **Ultrawide N-column** is just `gridCell(row:0, col:i, rows:1, cols:N)` → `(i/N, 0, 1/N, 1)`. No new code path — this is what "kills the 3×3 ceiling" mechanically.
- **Pixel gaps** (outer margin, inter-window gutter) are applied as insets after fraction resolution, so layouts stay resolution-independent.
- v1 ships a **tight default set** (halves, quarters, thirds, fullscreen) plus configurable grids. Arbitrary fractions are the engine's native unit, *not* a v1 user-facing layout DSL (that would be the platform identity we declined — `STRATEGY.md §4.2`).
- **v1 config surface is bounded:** grid dimensions are set via the M5 SwiftUI settings UI (row/column count fields only). There is **no** user-editable config file or layout-definition format in v1 — that is the declined config-DSL surface (`STRATEGY.md §4.2`). This keeps the identity constraint checkable during implementation.

## 6. Architecture

Four layers, single responsibility each. Events flow downward; no upward calls.

```
            ┌────────────────────────────────┐
            │   CGEventTap (session-level)   │   Layer 1: Capture
            │  observes kCGEventScrollWheel  │
            └────────────┬───────────────────┘
                         │ raw scroll event
                         ▼
       ┌─────────────────────────────────────────┐
       │  Finger-count source (§7)               │   Layer 2: Disambiguate
       │  MultitouchSupport primary / NSEvent PB │
       │  → exactly 2 contacts down?             │
       └────────────┬────────────────────────────┘
                    │ yes / no
                    ▼
   ┌───────────────────────────────────────────────┐
   │  Locate + decide — SYNCHRONOUS, in tap thread  │   Layer 3: Locate + decide
   │  fast geometry: CGWindowListCopyWindowInfo     │
   │  (or a cached window map) — NO AX here         │
   │  cursor in a window's titlebar band?           │
   │  → decide suppress / pass NOW                  │
   └────────────┬──────────────────────────────────┘
                │ if suppress: consume event + enqueue act
                ▼
         ┌───────────────────────────────────────┐
         │  Snap engine (§5) — OFF-THREAD        │   Layer 4: Act (swoosh.ax)
         │  AXUIElementCopyElementAtPosition →   │
         │  precise window-ref; resolve Frac-    │
         │  tionalRect; AXUIElementSetAttribute  │
         └───────────────────────────────────────┘
```

### 6.1 Threading model

| Layer | Thread / queue | Why |
|---|---|---|
| CGEventTap callback | Tap's runloop, dedicated background thread | Apple requires tap callbacks to return fast (<70 ms) or the tap is disabled |
| Suppression decision (fast geometry) | Inline in the tap callback | `CGWindowListCopyWindowInfo` / a cached window map is non-blocking; yields the synchronous suppress/pass answer without AX |
| Finger-count source | Framework's own callback thread (MTS) / main (NSEvent) | Reads only current contact count, atomic |
| AX locate + window placement | Serial queue `swoosh.ax` | `AXUIElementCopyElementAtPosition` and AX writes are blocking IPC; they run **only** in the off-thread *act* phase, never on the tap thread. Serializes writes (incl. divider-drag's paired writes) to avoid races |
| Settings UI | `@MainActor` | SwiftUI requirement |

The event-tap callback's only synchronous work is (1) reading the finger-count atomic, (2) for a matching scroll phase, consulting the fast geometry source to check whether the cursor is over a titlebar band, and (3) deciding suppress/pass **synchronously** from that. Only when it suppresses does it enqueue the precise AX locate + placement onto `swoosh.ax`. The blocking AX call never runs on the tap thread — this is what routes around FB11586064 *while still* honouring localized invocation (see §6.2).

### 6.2 Suppression strategy *(the hard part)*

Two-finger pan on a titlebar must be swallowed without breaking normal scrolling on that same titlebar (some apps embed a scroll view in a custom titlebar). The decision must be **synchronous and non-blocking** — a `CGEventTap` callback returns immediately and a swallowed event cannot be un-swallowed later, so the suppress/pass answer cannot wait on an AX hit-test. Consume the event only if **all three** hold, all checkable in-thread:

1. Exactly 2 active contacts (the finger-count atomic).
2. `kCGScrollWheelEventScrollPhase` is `kCGScrollPhaseBegan` or `kCGScrollPhaseChanged`.
3. **Fast geometry** (`CGWindowListCopyWindowInfo`, or a window-frame/titlebar map cached and refreshed off-thread) places the cursor inside the titlebar band of the frontmost standard window at that point — `[frame.minY, frame.minY + titlebarHeight]`.

If any fails, return the event unchanged. The precise `AXUIElementCopyElementAtPosition` hit-test (window-ref, `kAXStandardWindowSubrole` confirmation) runs later, off-thread, in the *act* phase — never here. Titlebar height defaults to 28pt; for tall/custom titlebars (Safari, Electron) derive it from real signals (§10), not a fixed attribute.

> ⚠️ **Known macOS hazards** (full detail in `DERISK.md`): the `.mayBegin` scroll phase was removed in Monterey (FB9724671) — do not depend on it; and a synchronous AX hit-test can block scroll up to ~500ms (FB11586064) — which is exactly why the suppress/pass decision uses fast in-thread geometry and the AX hit-test runs only off-thread in the act phase.

## 7. Finger-count source — MultitouchSupport primary, NSEvent Plan B

Per `STRATEGY.md §4.3`, the primary path is the private `MultitouchSupport.framework`; the public `NSEvent` path is a specced fallback.

```swift
protocol FingerCountSource {
    var contactCount: Int { get }   // atomic
    func start() throws
    func stop()
}
```

- **`MultitouchClient` (primary).** Loads `MultitouchSupport.framework` at runtime via `dlopen`/`dlsym` — **never** via SPM `.linkedFramework` — and registers `MTRegisterContactFrameCallback`. Gives precise, system-wide two-finger disambiguation (the reason Swish/Penc used it). Enumeration does **not** require Input Monitoring; whether the live contact *stream* requires it on macOS 26 is **untested** (a tracked v1 risk — `DERISK.md`, `spike/m0/RESULTS.md`).
- **`NSEventFingerCount` (Plan B).** Uses public touch APIs. Accepts some false negatives (e.g. Magic Mouse single-finger ambiguity) and weaker system-wide reliability. Its trigger conditions (when to auto-fall-back, or expose a toggle) live in `DERISK.md`. Both paths satisfy `FingerCountSource`, so Layers 1/3/4 are agnostic to which is active.

The fragility of the private path is the project's central technical risk; it is *managed*, not avoided, by the fixture harness (`DERISK.md`).

## 8. Permission flow

```
First launch
  ├── Onboarding window: explain why Accessibility is needed (titlebar hit-test + window move)
  ├── Open System Settings > Privacy & Security > Accessibility
  ├── Poll AXIsProcessTrustedWithOptions every 1s
  └── On grant → close onboarding, start event tap

If macOS native window tiling is detected enabled
  └── One-time alert: "macOS tiling will fight Swoosh's snaps. Disable it?"
      → Desktop & Dock > Windows > "Drag windows to screen edges to tile" = off
      → Dismissable with "I know what I'm doing"
```

We request **Accessibility only** (least privilege, `STRATEGY.md §5`). If the MultitouchSupport path requires Input Monitoring (M0: untested on macOS 26 — `spike/m0/RESULTS.md`), the onboarding gains a second, separately-justified prompt.

## 9. Key types (Swift API sketch)

Sketches, not final signatures — they establish the layer boundaries.

```swift
// Layer 1
final class EventTap {
    init(onScroll: @escaping (CGEvent) -> CGEvent?)
    func enable() throws
    func disable()
}

// Layer 2 — see §7 for FingerCountSource

// Layer 3 — fast, synchronous (tap thread): geometry only, NO AX
enum FastLocate {
    /// CGWindowListCopyWindowInfo / cached map — drives the synchronous
    /// suppress/pass decision (§6.2) and the divider-drag band check (§4.3).
    static func titlebarBandUnderCursor(at point: CGPoint) -> CGRect?
    static func sharedEdge(at point: CGPoint) -> Edge?
}

// Layer 4 locate — off-thread (swoosh.ax): precise AX
struct WindowHit {
    let window: AXUIElement
    let pid: pid_t
    let frame: CGRect            // AX global coords (top-left origin)
    let titlebarHeight: CGFloat  // derived per §10, NOT from a fixed attribute
}
enum HitTest {
    static func windowUnderCursor(at point: CGPoint) -> WindowHit?  // AXUIElementCopyElementAtPosition
    static func isOverTitlebar(_ hit: WindowHit, cursor: CGPoint) -> Bool
}

// Layer 4 — see §5 for SnapTarget / FractionalRect
enum SnapEngine {
    static func rect(for target: SnapTarget, on screen: NSScreen) -> CGRect
    static func apply(_ target: SnapTarget, to window: AXUIElement) throws
    static func resizePair(_ a: AXUIElement, _ b: AXUIElement, alongShared edge: Edge, to point: CGPoint) throws
}

// Restore history (§4.6)
struct FrameHistory {           // per-window ring buffer, default depth 4
    mutating func push(_ frame: CGRect)
    mutating func popPrevious() -> CGRect?
}

enum Direction {
    case left, right, up, down, upLeft, upRight, downLeft, downRight
    init?(scrollDelta: CGVector) // dominant axis + diagonal threshold
}
```

## 10. Edge cases & known issues

- **Stage Manager** re-tiles after AX placement; not officially supported in v1.
- **macOS native tiling** animations conflict with our placement; onboarding prompts to disable.
- **Native fullscreen** — placement is meaningless; the exit-fullscreen verb (§4.6) is the supported interaction, otherwise no-op.
- **Per-display scaling / Retina & coordinate spaces** — resolve the `FractionalRect` against the visibleFrame of the *screen containing the window's current center* (not the main screen). AX window position is **global, top-left origin, +y down, referenced to the primary display** — write it directly via `kAXPosition` with no flip. A flip to/from AppKit's bottom-left space is needed *only* if an intermediate computation uses `NSScreen` coordinates, and that flip must use the **primary** screen's height as the Y-reference, not the window's screen (which is wrong on a secondary display of different height). See §5.
- **Custom titlebars (Electron, Safari)** — there is **no** `kAXTitleBarHeightAttribute` in the SDK. Derive the titlebar band from real signals: the frames of AX title-UI elements (`kAXCloseButton` / `kAXFullScreenButton` subrole children, or the toolbar), or the gap between the window frame and its content-area frame, or a per-app override table — with 28pt as the documented fallback.
- **Windows refusing AX writes** (older Java, some Electron builds ignore `kAXPositionAttribute`) — log + no-op.
- **Coexistence with BetterTouchTool / Multitouch** — both contend for `MultitouchSupport` + `CGEventTap`, which can freeze the trackpad. Detect a competing client at launch and offer an explicit cooperative (listen-only) mode rather than a buried toggle. *(Designed-in, targeted for v1.1; tracked in `ROADMAP.md`.)*

## 11. Distribution & de-risk (cross-references)

- **Distribution:** self-owned Homebrew tap with `xattr` postflight now ($0); notarization is a deferred, reversible upgrade. Full rationale and the Sept 1 2026 cask-cutoff trigger: `STRATEGY.md §4.4` and `ROADMAP.md`.
- **De-risk:** the week-1 spike and the record-and-replay fixture harness that makes the private-API path maintainable: `DERISK.md`. **Hard rule:** any change to `EventTap` / the gesture recognizer must re-pass the `DERISK.md` matrix before merge.
