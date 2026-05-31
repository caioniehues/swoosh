---
title: "SwiftPM + Swift 6 macOS gotchas: case-collision, strict concurrency vs C interop, CGFloat formatting"
date: 2026-05-31
category: tooling-decisions
module: SwiftPM build / SwooshKit / SwooshUI
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "scaffolding a macOS-26 SwiftPM app that mixes pure logic with CGEventTap / AXUIElement / private-framework C interop"
  - "the package has both a SwiftPM Tests/ target and a sibling data directory whose name differs only in case"
  - "a SwiftUI Form binds a CGFloat setting and you reach for TextField(value:format:.number)"
  - "AX window geometry must be reconciled with AppKit NSScreen coordinates across multiple displays"
tags: [swiftpm, swift6, strict-concurrency, c-interop, case-insensitive-filesystem, cgfloat, swiftui, ax-coordinates]
---

# SwiftPM + Swift 6 macOS gotchas: case-collision, strict concurrency vs C interop, CGFloat formatting

## Context

Scaffolding Swoosh's real product tree (`Package.swift` + `Sources/`, the four-layer
architecture per SPEC §6) on macOS 26, after the throwaway M0 spike proved the risky surfaces.
Four problems surfaced that all "work on my machine" yet are either silent landmines or hard
compile errors. None is conceptual — each is a sharp edge where SwiftPM conventions, Swift 6
strict concurrency, SwiftUI's `FormatStyle` resolution, or the AX/AppKit coordinate split bites a
macOS app specifically. They are recorded together because they were all hit during a single
scaffolding pass and each has a concrete, committed fix in this repo.

A note on verification posture for this whole project: the pure logic (snap math, the
suppress/pass recognizer) and the fixture replayer are exercised in CI (`swift build` + `swift
test`, plus an `ast-grep` SPEC-invariant lint job — see `.github/workflows/ci.yml`); the live
trackpad, `MultitouchSupport` finger counts, `MTActuator` haptics, the `CGEventTap`, and the AX
writes are verified **only on real hardware**, not in CI. The gotchas below are split accordingly
— #3 is a build/compile observable; #1 is filesystem/checkout-dependent (it does **not**
reproduce on the case-insensitive macOS CI runner, only on a case-sensitive checkout); #2 is a
compile-time concurrency rule; #4 is logic that CI can cover but whose multi-display correctness
is ultimately a hardware check.

## Guidance

### 1. `Tests/` (SwiftPM) and a `tests/`-style data dir case-collide on APFS

SwiftPM mandates the test directory be named `Tests/` (capital T). If you also want a
`tests/fixtures/` data directory — the natural name from a plan doc (DERISK §2 literally
specifies `tests/fixtures/`) — the two paths differ only in the case of the first letter. On the
default **case-insensitive** APFS volume, `tests/` and `Tests/` are the **same directory**: your
fixture JSON silently lands inside the SwiftPM test target's tree. It builds, it runs, the tests
pass — and then it breaks the moment the repo is checked out on a case-**sensitive** volume,
where the two are distinct and the loader can't find the corpus. (This is why the bug is not
CI-observable here: the macOS CI runner is itself case-insensitive, so a reintroduced collision
would still pass there.)

**Fix:** give the data directory a collision-free top-level name. Swoosh uses `fixtures/` at the
repo root (not `tests/fixtures/`). The README records the reason explicitly so the deviation from
the plan doc isn't mistaken for drift (`fixtures/README.md`):

> Location note: DERISK §2 specifies `tests/fixtures/`; the corpus lives at top-level `fixtures/`
> instead, because `tests/` case-collides with SwiftPM's `Tests/` directory on case-insensitive
> macOS filesystems. Same role, collision-free path.

The test then locates the corpus by walking up from `#filePath` rather than assuming a working
directory, so it resolves the same way locally and in CI (`Tests/SwooshFixturesTests/CorpusTests.swift`):
three `.deletingLastPathComponent()` calls from the source file back to the repo root, then
`.appendingPathComponent("fixtures")`.

### 2. Swift 6 strict concurrency rejects the C-trampoline interop pattern; pin only the interop targets to `.v5`

The system-bridging layers rely on the canonical Cocoa pattern: a `@convention(c)` callback that
recovers `self` via `Unmanaged.fromOpaque(refcon)` and then mutates shared state read from another
thread. Swoosh does this in two places:

- `EventTap.trampoline` (`Sources/SwooshKit/EventTap.swift`) — a `CGEventTapCallBack` that does
  `Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()` and calls back into the instance,
  which mutates `latency` and `reenableCount`.
- `MultitouchClient.callback` (`Sources/SwooshKit/MultitouchClient.swift`) — an MT contact
  callback that recovers the client the same way and writes the live finger count, which the tap
  thread reads.

Swift 6's complete concurrency checking rejects this: the trampoline crosses an actor/Sendability
boundary the compiler can't reason about, and the bridging layer's mutable state is touched across
the tap thread, the `swoosh.mt` MT-callback thread, and the `swoosh.ax` serial queue (the latter
being where `SnapApplier`, also in `SwooshKit`, serializes its AX work).

**Fix:** keep the pure, fully-tested targets (`SwooshCore`, `SwooshFixtures`) in Swift 6 mode, and
set **only the interop targets** to Swift 5 language mode in `Package.swift` via
`swiftSettings: [.swiftLanguageMode(.v5)]`. In Swoosh that is `SwooshKit`, `SwooshUI`, and the
`swooshd` executable target. The package-level `// swift-tools-version: 6.0` stays; the language
mode is a per-target override, so you don't surrender Swift 6 across the whole package to satisfy
the C-bridging layer. The `Package.swift` comment documents the rationale inline so the `.v5`
pin reads as a deliberate confinement, not an oversight.

A macOS-26-only payoff worth noting: because the deployment floor is macOS 26, the shared
finger-count slot is a `Synchronization.Atomic<Int32>` with relaxed ordering
(`fingerCountAtomic` in `MultitouchClient`), single-writer (MT callback) / single-reader (tap
thread) — which replaces the M0 spike's C-shim atomic. Pinning the language mode is about the
trampoline/Sendability rejection, not about lacking a safe primitive.

### 3. `TextField(value:format:.number)` is ambiguous on a `CGFloat` binding

A SwiftUI numeric `TextField(value:format:)` with `.number` resolves its `FormatStyle` to one for
`Double` (or `Int`), not `CGFloat`. If your settings model stores a gap or threshold as `CGFloat`
(the natural type, since it flows into `CGRect` geometry), binding it directly to
`TextField(value: $x, format: .number)` is **ambiguous / type-mismatched** and won't compile
cleanly.

**Fix:** for a `CGFloat` control, use a `Stepper` or `Slider` (which take the binding directly and
don't route through a `FormatStyle`), or interpose an explicit `Double` proxy binding. In Swoosh
the `CGFloat`-typed settings are the pixel gaps (`outerGap` / `innerGap`), and
`Sources/SwooshUI/SettingsView.swift` drives them with `Stepper` —
`Stepper("Outer margin: \(Int(model.settings.outerGap)) pt", value: $model.settings.outerGap, in: 0 ... 40, step: 2)`
— formatting the displayed value with a plain `Int(...)` interpolation rather than a
`FormatStyle`. The continuous `commitThreshold` is a `Double` and uses a
`Slider(value: $model.settings.commitThreshold, in: 5 ... 100)`. No `TextField(value:format:)`
appears in the settings surface.

### 4. The NSScreen → AX coordinate flip must use the PRIMARY display height

AX window geometry (`kAXPosition` / `kAXSize`) is **global, top-left origin, +y down, referenced
to the primary display**. AppKit `NSScreen` is **bottom-left origin**. Any time an intermediate
computation goes through `NSScreen` (e.g. to get a screen's visible frame for snap math), you must
flip between the two spaces — and the Y reference for that flip is the **primary display's**
height, **not** the window's own screen height. Using the per-window screen height places windows
correctly on the primary display and **wrong** on a secondary display of a different height. This
is silent: single-monitor testing never reveals it.

**Fix:** centralize the flip and feed it the primary height. `Sources/SwooshCore/Geometry.swift`
exposes `Coordinates.flip(_ rect: CGRect, primaryHeight: CGFloat)` (its own inverse, so one call
maps either direction), and `Sources/SwooshKit/SnapApplier.swift` resolves the primary height once
via `primaryHeight()` — `NSScreen.screens.first { $0.frame.origin == .zero }` (the primary screen
is the one whose AppKit frame origin is `.zero`), falling back to `NSScreen.main` — and passes it
into every `Coordinates.flip(...)` call in `visibleFrameAX(containing:)`. Note that the final AX
write itself needs **no flip** (AX is already top-left global); the flip is only for the
`NSScreen`-sourced visible-frame intermediate. The doc comment in `Geometry.swift` states this
contract directly.

## Why This Matters

Three of these four are invisible on the machine that introduced them and only bite later or
elsewhere: the case-collision (#1) breaks on a case-sensitive checkout, the primary-height flip
(#4) breaks on a second monitor, and the strict-concurrency rejection (#2) is the one that fails
loudly — but the wrong reflex (dropping the whole package to Swift 5) throws away the safety the
pure core earns. The CGFloat formatting trap (#3) is a hard compile error that wastes time because
the obvious `.number` style looks correct. Recording the confinement boundaries (which targets are
`.v5`, where the flip reference comes from) keeps the SPEC invariants legible: private-SPI and
C-bridging stay in the `.v5` interop targets, pure logic stays in Swift 6, and AX-vs-AppKit
coordinate handling stays in one auditable place.

## When to Apply

- Setting up any SwiftPM package that pairs a `Tests/` target with a sibling data/fixtures dir —
  check for case-only name collisions before committing on APFS.
- Bridging `CGEventTap`, `AXUIElement`, IOKit, or a `dlopen`'d private framework from Swift 6 —
  expect to pin the bridging target(s) to `.swiftLanguageMode(.v5)` while keeping pure targets on
  6.
- Building SwiftUI numeric controls over `CGFloat` model values.
- Reconciling AX (top-left, primary-referenced) geometry with AppKit `NSScreen` (bottom-left) in
  any multi-display-capable macOS app.

## Examples

Per-target language-mode pinning in `Package.swift` (Swift 6 package, Swift 5 interop targets):

```swift
// swift-tools-version: 6.0
.target(name: "SwooshCore"),                                   // pure → Swift 6
.target(name: "SwooshFixtures", dependencies: ["SwooshCore"]), // pure → Swift 6
.target(name: "SwooshKit", dependencies: ["SwooshCore", "SwooshFixtures"],
        swiftSettings: [.swiftLanguageMode(.v5)]),             // C interop → Swift 5
.target(name: "SwooshUI", dependencies: ["SwooshCore", "SwooshKit"],
        swiftSettings: [.swiftLanguageMode(.v5)]),
.executableTarget(name: "swooshd", dependencies: ["SwooshKit"],
        swiftSettings: [.swiftLanguageMode(.v5)]),
```

The trampoline pattern that forces the `.v5` pin (`EventTap.swift`):

```swift
private static let trampoline: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    return me.handle(type: type, event: event)   // mutates latency / reenableCount
}
```

The flip helper and its primary-height contract (`Geometry.swift` + `SnapApplier.swift`):

```swift
// Geometry.swift — its own inverse; primaryHeight must be the PRIMARY display's height.
public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}

// SnapApplier.swift — resolve the primary height once, use it for every flip.
private static func primaryHeight() -> CGFloat {
    (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0
}
```

Working-directory-independent corpus location (`CorpusTests.swift`):

```swift
var corpusDir: URL {
    URL(fileURLWithPath: #filePath)        // .../Tests/SwooshFixturesTests/CorpusTests.swift
        .deletingLastPathComponent()       // .../Tests/SwooshFixturesTests
        .deletingLastPathComponent()       // .../Tests
        .deletingLastPathComponent()       // repo root
        .appendingPathComponent("fixtures")
}
```

## Related

- `docs/solutions/tooling-decisions/macos-private-api-spike-findings.md` — the M0-spike findings (that spike is swiftc-direct with NO SwiftPM; this doc is the SwiftPM build path — don't conflate the two).
- `Package.swift` — the per-target `.swiftLanguageMode(.v5)` pins and the inline rationale comment.
- `Sources/SwooshKit/EventTap.swift`, `Sources/SwooshKit/MultitouchClient.swift` — the
  `@convention(c)` trampoline + `Unmanaged.fromOpaque(refcon)` patterns that require Swift 5 mode.
- `Sources/SwooshCore/Geometry.swift`, `Sources/SwooshKit/SnapApplier.swift` — the AX↔AppKit flip
  and the primary-height resolution.
- `Sources/SwooshUI/SettingsView.swift` — `Stepper` over the `CGFloat` gaps, `Slider` over the
  `Double` threshold, no `TextField(value:format:)`.
- `fixtures/README.md`, `Tests/SwooshFixturesTests/CorpusTests.swift` — the case-collision-avoiding
  corpus location and its `#filePath`-relative loader.
- SPEC §5/§6/§7/§10, DERISK §2 — the architecture, threading, private-SPI confinement, and
  coordinate contracts these fixes uphold.
