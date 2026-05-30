# M0 De-Risk Spike — RESULTS (go / no-go)

> The durable artifact that outlives the spike. It is the input to the M1 go
> decision. Plan: `docs/plans/2026-05-30-001-feat-m0-derisk-spike-plan.md`.
>
> **Status: INTERIM — macOS 26 cell COMPLETE. All four criteria green on this OS:
> S1 suppress proven & titlebar-scoped (normal scroll intact, felt), S2 live count ✅,
> S3 AX write ✅, S4 felt ✅; a contact-stream use-after-free was found + fixed along
> the way. macOS 14/15 remain entirely pending, and one perf item (off-thread
> band-check cache) is carried into M1.** Do not read any "go" into this yet — the gate
> needs S1–S4 green on all three OSes.

## How to complete it

On **each** of macOS 14, 15, 26 — ideally with an external Magic Trackpad —
grant the built binary Accessibility + Input Monitoring, then run:

```sh
M0_LISTEN=1 M0_TAP=1 M0_AX=1 M0_HAPTIC=1 sh spike/m0/run-matrix.sh
# add M0_DWELL_MS=<n> on a suppress run to measure the disable threshold
```

Fold each `build/results/m0-macos-<ver>.jsonl` into the matrix below.

## S1–S4 × {14, 15, 26} matrix

Legend: ✅ pass · ◐ partial · ✗ fail · ⏳ pending (needs hardware/grant).

| Criterion | macOS 14 | macOS 15 | macOS 26 (this machine) |
|---|---|---|---|
| **S1** capture & suppress | ⏳ | ⏳ | ✅ **suppression PROVEN, titlebar-scoped** — 64 events swallowed, live 2-finger feed (919 frames), `Began` seen, **normal scroll intact (felt — pivot trigger NOT fired)**. ⚠️ in-thread band check max ~20.8ms vs sustained-15ms disable threshold → off-thread cache is a carried-forward M1 task |
| **S2** finger count | ⏳ | ⏳ | ✅ live count — 919 frames in ~12s (~77Hz), maxFingers 2, clean 0/1/2 transitions; enumeration + UAF-fixed startup ✅ |
| **S3** AX locate + act | ⏳ | ⏳ | ✅ move/resize landed (+20pt nudge under cursor, read-back exact, restored) |
| **S4** haptics (background) | ⏳ | ⏳ | ✅ open/actuate/close = kIOReturnSuccess **and felt** (human-confirmed, built-in trackpad) |

### What IS already proven on macOS 26.5 (arm64)

These ran green here and retire real risk for the 26 cell:

- **Build + load (KTD2):** the spike compiles (`swiftc`, Swift+C bridge) and the
  bare ad-hoc-signed binary `dlopen`s the private `MultitouchSupport` framework
  and resolves **all 14 required symbols** (finger-count + `MTActuator` families).
- **ABI drift guard (R17):** `sizeof(MTTouch) == 96` holds.
- **Relaxed atomic (KTD8):** the C-shim single-writer/single-reader atomic round-trips.
- **Device enumeration (S2 non-TCC part):** `MTDeviceCreateList` returns the
  built-in trackpad with Input Monitoring **denied** (no prompt), `MTDeviceIsBuiltIn`
  classifies it, and **`MTDeviceGetDeviceID` returns a valid ID** — so the official
  accessor works and the `mactic` offset-64 struct hack is **not** needed.

### Session 2026-05-30 (macOS 26.5, arm64, built-in trackpad) — automated pass

Run unattended with both TCC grants live (Accessibility + Input Monitoring now
**granted** on this machine — the seed below was captured when both were denied):

- **S3 AX move/resize ✅ (KTD7).** `M0_AX=1 … axact` hit-tested an `AXStandardWindow`
  under the cursor, ran the size→position→size sequence to nudge it +20pt, and the
  read-back matched the target exactly (`landed:true`) before restoring. The
  off-thread `swoosh.ax` act path lands writes on a live window on this OS.
- **S1 active tap install ✅.** `M0_TAP=1 … suppress` created the `.cgSessionEventTap`
  (`tap.create ok:true`, `axTrusted:true`), ran the never-block loop, and tore down
  clean (exit 0). The *suppress decision* is still finger-gated (see matrix).
- **S4 actuator IOReturn ✅.** `M0_HAPTIC=1 … haptics` returned `kIOReturnSuccess` on
  open **and** actuate **and** close from a bare background binary. Necessary, not
  sufficient — the felt tap is the remaining oracle.
- **Bug found + fixed — contact-stream use-after-free.** The first real run of the S2
  listen path (`M0_LISTEN=1 … fingers`) crashed `EXC_BAD_ACCESS` in
  `__CFCheckCFInfoPACSignature` ← `CFRunLoopRun` ← `MultitouchClient.startListening`.
  Cause: `enumerate()` let the `MTDeviceCreateList` `CFArray` release at function
  scope, dangling every `MTDeviceRef`; `MTDeviceStart` then wired a freed device into
  the run loop. Fix: retain the array for the client's lifetime (`deviceList`). Both
  the listen path and the new combined probe now run crash-free.
- **Combined S1+S2 probe wired.** `M0_TAP=1 M0_LISTEN=1 … suppress` now starts the
  MultitouchSupport stream and the tap **in one process sharing the one KTD8 atomic**,
  so the tap reads a live finger count — the wiring S1 end-to-end suppression needs
  (resolves the old TESTING.md caveat). `M0_SECONDS=<n>` widens the capture window.

### Session 2026-05-31 (macOS 26.5, built-in trackpad) — finger-driven S1/S2 + felt S4

Caio ran the combined probe + dwell-sweep + haptics by hand. The load-bearing results:

- **S1 suppression PROVEN.** Combined run (`M0_SECONDS=12 M0_TAP=1 M0_LISTEN=1 suppress`):
  `suppressed:64` of `callbacks:547`, `liveMaxFingers:2`, `liveFramesSeen:919`. The tap
  swallowed two-finger titlebar-pan scroll events while the live finger count fed it through
  the shared atomic; 483 events passed through — suppression was scoped to the titlebar band,
  not bleeding into ordinary scrolling. `firstPhases:[128,1,2,2,…]`, `sawMayBegin:true`.
  **Caio confirmed by feel: normal two-finger scrolling over window bodies stayed completely
  normal — the DERISK §1 pivot trigger ("suppression breaks normal scroll → abort") did NOT
  fire.** S1's thesis (claim titlebar pans, leave ordinary scroll untouched, no kext) holds.
- **S2 live count PROVEN.** `mt.count` logged clean 0→1→2→1→0 transitions; 919 frames in ~12s
  (~77Hz). Input Monitoring granted; the contact stream is live and accurate.
- **S4 felt CONFIRMED.** Human felt the actuation (IOReturn already 0). S4-26 closes.
- **⚠️ Latency finding (the real catch).** The in-thread `CGWindowListCopyWindowInfo` band
  check hit **max 20.8ms** (no dwell), and a sustained 15ms/callback dwell trips
  `kCGEventTapDisabledByTimeout`. So the in-thread titlebar check can approach the disable
  ceiling — exactly the "off-thread cache vs in-thread fork" open question
  (`EventTapProbe.swift`), validating SPEC §6.2's off-thread geometry cache as MANDATORY for
  M1. Only `max` is instrumented; the p50/p95 distribution (cold-start outlier vs typical?)
  is the next measurement. **Decision (Caio): recorded as a carried-forward M1 task, not
  pursued further this session — the de-risk question (is suppression possible without
  breaking normal scroll?) is already answered yes, so chasing the perf budget now would be
  doing M1's work inside M0.**
- **Benign chatter:** MultitouchSupport printed `*** Recognized (0x6f) family*** (30 cols X 22
  rows)` on stream start — the framework recognizing the trackpad sensor grid. Harmless.

## Numeric performance baseline (R9) — PENDING

Filled from the hardware runs; none are measurable without the active tap + load:

- Measured per-OS `kCGEventTapDisabledByTimeout` threshold (dwell-sweep, N runs + variance):
  **macOS 26:** a sustained **15ms**/callback dwell tripped the timeout on both runs (tap
  re-armed automatically, `tap.reenabled reason:timeout`); a single ~20.8ms real callback did
  NOT trip it. So the ceiling is nuanced (cumulative/sustained, not a clean per-callback line)
  and 15ms sustained is already over — refine with a **downward** sweep (5/8/10/12ms) to find
  where timeouts stop. **14/15:** ⏳
- Callback p50/p95/p99/p999/max under the adversarial matrix:
  **macOS 26:** **max 20.8ms** over 547 callbacks (in-thread `CGWindowListCopyWindowInfo` band
  check, no dwell). Only the max is instrumented today — p50/p95/p99 need a percentile sample.
  The max blows the SPEC ≤~1ms budget → the in-thread band check is the latency hazard;
  off-thread geometry cache (SPEC §6.2) is mandatory for M1. **14/15:** ⏳
- Contact-stream frame rate: **macOS 26:** 919 frames in ~12s ≈ **77 Hz**. **14/15:** ⏳
- Max `swoosh.ax` queue depth under burst (bounded?): ⏳
- End-to-end gesture→window-moved latency (informational, not an SLA): ⏳
- Measurement machine class / lowest-spec target: macOS 26 cell = this machine; 14/15 ⏳

## Forced go/no-go decisions — PENDING measurement

These do **not** auto-resolve to "go"; each needs a recorded decision once measured:

- **KTD6 — Input Monitoring required?** On this machine `IOHIDCheckAccess(listenEvent)`
  now reports `granted` (the seed was captured when it read `denied`). The open
  question is unchanged: whether contact frames arrive *only* with Input Monitoring
  granted is the `M0_LISTEN=1` granted-vs-revoked measurement (needs actual touch, so
  still pending). **If required on any OS:** record the
  strategy resolution (accept the second permission and revise `STRATEGY.md §5` /
  origin R39, **or** invoke the NSEvent Plan B to hold least-privilege) before M1.
- **MTActuator as a 4th private surface?** Symbols resolve; if felt actuation
  confirms the private path is load-bearing, record the trade-off (ship haptics at
  4 private surfaces vs. degrade to hold the 3-surface auditability story) and
  append `MTActuator` to the `STRATEGY.md §5` ledger / origin R46 — in the **same
  commit** that finalizes this file.

## Pivot triggers (R8)

- S1 unprovable jank-free → **abort** (suppression impossible). **macOS 26: NOT triggered —
  suppression proven titlebar-scoped, normal scroll intact (felt). 14/15 still to confirm.**
- S2 unreliable / struct drift → **NSEvent Plan B** for finger-count. **macOS 26: NOT triggered
  — live count clean @ ~77Hz, `sizeof(MTTouch)==96` held.**
- S4 unprovable on the private path → **ship without haptics** (degrade). **macOS 26: NOT
  triggered — felt actuation confirmed on the private MTActuator path.**

### Carried into M1 (does not block the gate)

- **Off-thread geometry cache (SPEC §6.2).** The in-thread `CGWindowList` titlebar-band check
  measured ~20.8ms max — over budget against a sustained-15ms disable threshold. M1 must serve
  the band check from a cache maintained off the tap thread and prove the callback fits the
  budget. Add p50/p95/p99 callback instrumentation when doing so (R9 baseline).

## Verdict

**PENDING — macOS 26 cell complete; 14/15 outstanding.** On macOS 26 all four criteria are
green: **S1 suppression proven and titlebar-scoped (normal scroll intact, felt — pivot trigger
NOT fired), S2 live count ✅, S3 AX write ✅, S4 felt ✅.** The hardest existential risk — can
we claim titlebar pans without breaking normal scroll, no kext — is retired on this OS. One
performance item is carried into M1 (off-thread geometry cache for the band check); it does
not block the de-risk decision. macOS **14 and 15 remain entirely untouched** — run
`M0_LISTEN=1 M0_TAP=1 M0_AX=1 M0_HAPTIC=1 sh spike/m0/run-matrix.sh` on each. **No "go" until
S1–S4 are green on all three OSes.**
