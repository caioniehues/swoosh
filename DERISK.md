# Swoosh — De-risk

> How we prove the risky parts work before building anything else, and how we keep them working across macOS releases. Strategy: [`STRATEGY.md`](./STRATEGY.md). Technical design: [`SPEC.md`](./SPEC.md). Sequencing: [`ROADMAP.md`](./ROADMAP.md).
>
> Last updated 2026-05-31 (M0 gate GO on macOS 26; latest-macOS-only scope).

## Why this doc exists

Swoosh composes public APIs (`CGEventTap`, `AXUIElement`) with private/undocumented ones — `MultitouchSupport.framework` (finger-count), likely `MTActuator` (haptics), and the `"AXFullScreen"` attribute — none of the private surfaces carrying a stable ABI. That fragility is exactly what made the last free-gesture window manager — **Penc** — go dormant (`STRATEGY.md §1`). Our answer is not to avoid the private path (the public one can't do system-wide titlebar gestures — `SPEC.md §7`) but to **de-risk it up front and then keep it covered with replayable tests forever.** De-risk is therefore two things: a one-time go/no-go **spike**, and a permanent **fixture harness**.

The anti-Penc metric (`STRATEGY.md §7`): the fixture corpus catches a real macOS-beta regression *before* a user reports it.

## 1. The week-1 spike (go / no-go gate)

A small throwaway program — no UI, no settings, no packaging — that proves the load-bearing mechanisms on real hardware. **Nothing else gets built until all four criteria pass.** If a criterion can't pass, the project pivots (to the NSEvent Plan B, to the `MTActuator` haptics path, or — if suppression itself is impossible — not at all).

| # | Criterion | Pass condition |
|---|---|---|
| **S1 — Capture & suppress** | A session `CGEventTap` decides suppress/pass **synchronously from fast geometry** (`CGWindowListCopyWindowInfo`, no AX on the tap thread) and swallows a two-finger scroll on a window titlebar while letting normal scroll through *on the same titlebar* | No visible scroll jank anywhere; normal two-finger scroll in document areas is untouched; the titlebar pan is consumed; the decision never blocks the tap thread |
| **S2 — Finger count** | `MultitouchSupport` via `dlopen`/`dlsym` + `MTRegisterContactFrameCallback` reports an accurate, low-latency contact count | Count flips 0→2→0 within one frame of physical touch; Input Monitoring requirement on macOS 26 untested (IM-denied case not run) |
| **S3 — Locate & act** | `AXUIElementCopyElementAtPosition` (off-thread) resolves the window under the cursor, classifies the titlebar band, and a test `kAXPosition`/`kAXSize` write lands | Correct window identified across Finder/Safari/an Electron app; write visibly moves the window; the AX call runs off the tap thread (see FB11586064 below) |
| **S4 — Haptic actuation** | A ready/done tap actuates from the **background, non-frontmost** event-tap context on an **external** Magic Trackpad | A tap is felt on commit; if `NSHapticFeedbackManager` can't actuate in that context, the private `MTActuator` path does (**M0: confirmed felt on macOS 26**; added to the capability ledger — `STRATEGY.md §5`) |

**Test matrix:** run S1–S4 on **macOS 26 (latest; the only supported target as of 2026-05-31)**. A criterion is "passed" when green on macOS 26. *Result: all four GREEN — gate resolved **GO** (`spike/m0/RESULTS.md`).*

### Hazards the spike must confront (not discover in production)

- **FB9724671 — `.mayBegin` scroll phase removed in Monterey.** It silently vanished and broke Swish. Do **not** depend on `.mayBegin`; suppression keys off `kCGScrollPhaseBegan` / `kCGScrollPhaseChanged` only (`SPEC.md §6.2`).
- **FB11586064 — synchronous AX hit-test can block scroll up to ~500ms.** This is why the suppress/pass decision uses fast, in-thread geometry (`CGWindowListCopyWindowInfo`) and the AX hit-test runs only off-thread in the act phase on the `swoosh.ax` queue (`SPEC.md §6.1–6.2`). The spike must demonstrate zero tap-thread blocking, not just "it works."
- **Private-API permission drift.** `MultitouchSupport` *enumeration* needs no Input Monitoring; whether the live contact *stream* requires it on macOS 26 is **untested** (the IM-denied case wasn't run) — a tracked risk, closable by a 30-sec IM-denied test (`spike/m0/RESULTS.md`, `SPEC.md §7`).

## 2. The fixture format (record)

A **capture mode** — a hidden runtime toggle (a `defaults` key), shipped in *release* builds so non-developers can record fixtures with no toolchain (`CONTRIBUTING.md`) — records, during real live use, the exact inputs each layer saw, time-aligned, to an on-disk fixture:

- **Layer 1:** the `CGEventTap` scroll + mouse-drag event stream (phase, delta, location).
- **Layer 2:** the `MultitouchSupport` contact-frame stream (contact count + timestamps per frame).
- **Layer 3a (synchronous decision):** the fast-geometry result at the cursor (frontmost window frame + titlebar band) that drives the suppress/pass decision — the actual input to the §6.2 gate.
- **Layer 3b (act):** the AX hit-test *results* (resolved window subrole, frame) — recorded as resolved values, not live AX handles, so they replay without the original apps running.
- **Decision log:** for each event, what Swoosh *decided* (suppress / pass, target resolved, frame written).

A fixture is a single self-contained file (one gesture or short session). Fixtures live in `fixtures/` — the originally-specced `tests/fixtures/` would case-collide with SwiftPM's `Tests/` directory on case-insensitive macOS filesystems — and are the lowest-bar community contribution (`CONTRIBUTING.md`).

> Caveat to design around: a fixture of a private-API stream may itself drift across macOS versions (the contact-frame struct layout could change). The capture records the *decoded* contact count plus the raw frame, so a struct change is detectable as "raw present, decode mismatched" rather than a silent wrong answer.

## 3. The headless replayer (replay)

A test target that feeds a fixture back through Layers 1–3 **with no trackpad and no AX targets**, then diffs the produced decision log against the fixture's recorded decisions.

- Runs in CI on every PR (no special hardware needed).
- A diff is a regression: the recognizer now decides differently than the recorded-correct behavior.
- This is what turns "Layers 1–2 are manual-test-only" (the old spec's admission) into "Layers 1–3 are covered by replayable assertions."

## 4. The macOS-beta canary

When a new macOS beta ships, run a **single script** that replays the full fixture corpus and diffs decisions against the recorded baseline, surfacing the *precise* failing assertion (which layer, which fixture, expected-vs-actual) — not "it broke." For a solo, pre-v1 project this is run **manually on a real-hardware Mac** (or via a minimal CI config); the self-hosted runner + auto-issue-filing is a **post-v1** upgrade for when a community is generating fixtures and regressions to triage. The script is a thin wrapper over the §3 replayer, which already exists.

**What the canary does *not* cover** (be honest about it): it replays *existing* fixtures. Validating genuinely new OS behavior still needs a human on real trackpad hardware to *record* fresh fixtures (§2) — and detection only matters if the maintainer is present to fix what it finds (`STRATEGY.md §6.1`). It depends on the fixture format (§2) existing first, which is why the harness is built **alongside the snap engine in M1**, not bolted on later (`ROADMAP.md`).

## 5. NSEvent Plan B triggers

The public `NSEvent` path (`SPEC.md §7`) is promoted from fallback to default **only if** one of these fires, and the decision is recorded here when it does:

- S2 fails on a future macOS (MultitouchSupport count becomes unreliable or starts requiring Input Monitoring with no user-acceptable prompt).
- The canary shows MultitouchSupport decoding breaking on >1 consecutive release with no tractable fix.
- A notarization/distribution requirement makes shipping the private framework untenable.

Until then: MultitouchSupport is load-bearing, NSEvent is the specced safety net behind the same `FingerCountSource` protocol.

## 6. The hard rule

**Any change to `EventTap` or the gesture recognizer must re-pass the §1 spike matrix (or its automated equivalent via the replayer) before merge.** Suppression and finger-count are the two mechanisms most likely to break invisibly; they get the strictest gate in the project.
