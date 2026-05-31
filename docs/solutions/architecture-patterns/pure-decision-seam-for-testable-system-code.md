---
title: Pure decision functions make hardware-dependent macOS system code CI-testable
date: 2026-05-31
category: architecture-patterns
module: SwooshCore + SwooshFixtures (recognizer + replayer)
problem_type: architecture_pattern
component: testing_framework
severity: medium
applies_when:
  - "A correctness decision must run inside an un-testable I/O boundary (a CGEventTap callback, an AX write queue, a kernel/driver callback)"
  - "The live behavior can only be confirmed on real hardware, but the decision logic is pure and could be tested in CI"
  - "A silent regression in that decision (e.g. swallowing a scroll event that should pass) would be expensive to catch manually"
tags: [pure-functions, event-tap, accessibility-api, fixture-replay, ci-testability, seam, regression-detection]
---

# Pure decision functions make hardware-dependent macOS system code CI-testable

## Context

Swoosh suppresses two-finger trackpad gestures on window titlebars by installing a
`CGEventTap`. The tap callback runs on a real input thread, reads a live finger count from a
`dlopen`-loaded private framework, and — on a "this is our gesture" decision — writes window
frames through the Accessibility API on a serial queue. None of that I/O is reproducible in CI:
there is no trackpad, no real apps, and no AX tree on a headless runner. The live trackpad + AX
behavior is verified on real hardware, not in CI.

The trap is that the *consequential* logic lives right inside that un-testable boundary. The
gate that decides suppress-vs-pass is exactly the part a regression would silently break (swallow
a normal scroll → broken scrolling, the project's stated pivot trigger per `DERISK.md §1`), and
it is the part hardest to test by hand. If the decision is tangled into the callback, the only
way to test it is on hardware.

The pattern Swoosh uses: pull every *decision* out of the I/O boundary into a dependency-light
target of pure functions (`SwooshCore`), leave only the I/O glue in the live layer (`SwooshKit`),
and feed recorded inputs back through the *same* pure function in CI (`SwooshFixtures`). A live
regression and a CI failure become one code path.

## Guidance

1. **Name the synchronous inputs the decision actually needs, as a plain value.** Swoosh's
   `RecognizerInput` (`Sources/SwooshCore/Recognizer.swift`) is a `Sendable`, `Codable`,
   `Equatable` struct of exactly the data the gate can see without an AX hit-test: `contactCount`,
   `phase` (`ScrollPhase`), `isContinuous`, `cursor`, and a pre-computed `titlebarBand: CGRect?`.
   Critically the geometry is *already resolved* into the input — the pure function never reaches
   back into the cache. That is what makes it serializable and replayable.

2. **Make the decision a static pure function with a small closed output.**
   `Recognizer.decide(_ input: RecognizerInput) -> Decision` (`.pass` / `.suppress`) holds no
   state and touches no system API. It is conservative by construction: it suppresses only if all
   conditions hold, and any miss (including a `nil` `titlebarBand` from a cache miss) degrades to
   `.pass` — it never blocks to recompute, because a swallowed event cannot be un-swallowed.

3. **Keep the live layer as thin glue that builds the input and calls the function.**
   `GestureService.decide(_ event: CGEvent)` (`Sources/SwooshKit/GestureService.swift`) reads the
   finger atomic (`fingers.contactCount`), the scroll phase, and `cache.titlebarBand(at:)`,
   assembles a `RecognizerInput`, then calls `Recognizer.decide(input)` — the *same* function the
   replayer tests. On suppress it returns `nil` to consume the event and, for a committed swipe,
   hands off to the AX path off-thread via `SnapApplier`. The callback itself does no correctness
   reasoning.

4. **Record the input + the recorded-correct decision; replay through the same function; diff.**
   `Replayer.replay(_ fixture: Fixture)` (`Sources/SwooshFixtures/Replayer.swift`) iterates a
   fixture's samples, calls `Recognizer.decide(sample.input)`, and compares to
   `sample.recordedDecision`. Any disagreement is a `ReplayDiff` (a regression). No trackpad, no
   AX, no apps. A fixture is a flat JSON file (`fixtures/titlebar-pan-left.json`) with scalar
   fields, so a non-developer can hand-edit one.

5. **Add a positive control so the harness can fail.** A regression detector that can only pass is
   worthless. `ReplayerTests.testDetectsRegression`
   (`Tests/SwooshFixturesTests/ReplayerTests.swift`) records an input it first asserts decides
   `.pass`, but stores the baseline as `.suppress` — a *planted* wrong baseline — then asserts the
   replayer reports exactly one diff with `expected == .suppress`, `actual == .pass`. If that test
   ever passes silently, the canary is blind.

6. **Apply the same seam to every decision, not just the gate.** Swoosh extracts the whole
   decision surface into pure `SwooshCore`:
   - swipe → target: `SwipeGesture` (delta accumulation + `committedDirection`, `Swipe.swift`) and
     `SwipeResolver.target(for:currentState:)`.
   - state classification: `SnapClassifier.classify(frame:in:tolerance:)` (`SnapClassifier.swift`).
   - divider geometry: `DividerLocator.divider(at:among:)` and
     `DividerResolver.resize(leading:trailing:orientation:to:)` (`Divider.swift`) operate on
     `[WindowFrame]` value types, not live windows.
   - fraction math: `SnapEngine.rect(for:in:)` / `gridFraction(row:col:rows:cols:)` (`SnapEngine.swift`).
   - keyboard bindings: `KeyBindings.action(for:in:)` / `numpadGridCell(_:)` (`KeyBindings.swift`).

   The result is 73 fast unit tests covering the decisions, while the unverifiable AX/tap/finger
   I/O glue stays minimal.

## Why This Matters

- **The expensive-to-catch logic becomes the cheap-to-test logic.** The suppress/pass gate is
  both the most consequential code (a wrong suppress breaks normal scrolling) and the hardest to
  exercise by hand. Extracting it makes it the *easiest* thing to assert.
- **One code path for "live regression" and "CI failure."** Because `GestureService` and
  `Replayer` call the *identical* `Recognizer.decide`, a fixture that fails in CI proves the live
  tap would mis-decide that exact input. There is no second, drifting "test implementation."
- **It honors the project's hard rule cheaply.** `CLAUDE.md` / `DERISK.md §1` require any change
  to the recognizer to re-pass the suppression matrix. With the seam, "re-pass the matrix" is a
  CI run (`swift test`) over the fixture corpus, not a hardware session — and the same corpus is
  the macOS-beta canary (`DERISK.md §4`) that catches an OS update silently changing scroll-phase
  semantics.
- **It does not over-promise.** This makes the *decisions* testable in CI. It does not test the
  trackpad, the AX writes, the haptics, or the `dlopen`'d finger count — those stay hardware-only.
  The seam draws an honest line: pure logic + the fixture replayer in CI, real-hardware behavior
  out of band.

## When to Apply

Apply when a correctness decision is trapped inside an I/O boundary you cannot drive in CI
(event taps, AX/UI-automation callbacks, driver/IPC callbacks) AND the decision is — or can be
made — a pure function of a small, serializable set of inputs.

Apply especially when a silent wrong answer is costly and the only current test is "try it on the
machine."

Do **not** bother when the I/O *is* the thing under test (you can't unit-test that the trackpad
reports two fingers), or when the decision is trivial and has no regression surface. The seam pays
off in proportion to how consequential and how un-testable-in-place the decision is.

When you build the replayer, always ship a positive-control fixture/test that proves it can fail.

## Examples

The seam in three places, all calling one function:

Pure decision (`Sources/SwooshCore/Recognizer.swift`) — note the conservative degrade-to-pass:

```swift
public static func decide(_ input: RecognizerInput) -> Decision {
    guard input.isContinuous else { return .pass }            // discrete mouse wheel
    guard input.contactCount == 2 else { return .pass }       // exactly two fingers
    guard input.phase == .began || input.phase == .changed else { return .pass } // never mayBegin
    guard let band = input.titlebarBand, band.contains(input.cursor) else { return .pass }
    return .suppress
}
```

Live glue (`Sources/SwooshKit/GestureService.swift`) — build the input, call the same function:

```swift
let input = RecognizerInput(
    contactCount: fingers.contactCount,
    phase: phase,
    isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1,
    cursor: cursor,
    titlebarBand: cache.titlebarBand(at: cursor)
)
let decision = Recognizer.decide(input)
capture?.record(input: input, decision: decision)
// ...
return decision == .suppress ? nil : event
```

Headless replay (`Sources/SwooshFixtures/Replayer.swift`) — same function, diff vs baseline:

```swift
for (i, sample) in fixture.samples.enumerated() {
    let actual = Recognizer.decide(sample.input)
    let expected = sample.recordedDecision
    if actual != expected {
        diffs.append(ReplayDiff(index: i, expected: expected, actual: actual, input: sample.input))
    }
}
```

The positive control that proves the replayer can fail
(`Tests/SwooshFixturesTests/ReplayerTests.swift`):

```swift
let passInput = input(count: 1)
XCTAssertEqual(Recognizer.decide(passInput), .pass)   // really decides .pass
// ...recorded with decision: .suppress — a planted regression
let result = Replayer.replay(fixture)
XCTAssertFalse(result.passed)
XCTAssertEqual(result.diffs.first?.expected, .suppress) // recorded baseline
XCTAssertEqual(result.diffs.first?.actual, .pass)       // current recognizer
```

The flat, hand-editable on-disk fixture (`fixtures/titlebar-pan-left.json`) — scalar `bandX/Y/W/H`
rather than a nested `CGRect`, so all four present together means "titlebar under cursor" and all
absent means "none":

```json
{ "t": 0.0, "contactCount": 2, "phase": 1, "isContinuous": true,
  "cursorX": 400, "cursorY": 14,
  "bandX": 0, "bandY": 0, "bandW": 800, "bandH": 28, "decision": "suppress" }
```

## Related

- `docs/solutions/tooling-decisions/macos-private-api-spike-findings.md` — the M0-spike findings; that doc states the runtime threading contract this seam makes testable.
- `SPEC.md §6.2` — the suppress/pass gate this seam implements; `§6` — the four-layer architecture
  (event-tap callbacks must not block; AX writes go on the `swoosh.ax` serial queue).
- `DERISK.md §1` — the suppression matrix the recognizer must re-pass on every change; `§2` — the
  fixture schema (Layers 1–3a, recorded raw contact frame); `§3` — the headless replayer; `§4` —
  the macOS-beta canary that runs the corpus.
- `Sources/SwooshFixtures/Fixture.swift` — the flat JSON schema, `Sample.init(t:input:decision:rawContactFrame:)`
  recorder convenience, and `Sample.input` / `recordedDecision` reconstruction;
  `Sources/SwooshFixtures/FixtureRecorder.swift` — the capture-side recorder.
- `Sources/SwooshCore/{Swipe,SnapClassifier,SnapEngine,Divider,KeyBindings}.swift` — the rest of
  the pure decision surface that lives behind the same seam.
- `CLAUDE.md` (Implementation philosophy) — "The hard part is suppression, not snap math"; build
  the fixture harness *with* the engine.
