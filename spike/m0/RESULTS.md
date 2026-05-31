# M0 De-Risk Spike — RESULTS (go / no-go)

> The durable artifact that outlives the spike. It is the input to the M1 go
> decision. Plan: `docs/plans/2026-05-30-001-feat-m0-derisk-spike-plan.md`.
>
> **Status: GO (macOS-26 basis). Scope decision 2026-05-31: Swoosh targets the LATEST
> macOS only — macOS 14/15 are OUT OF SCOPE (no backward-compat). The M0 gate is therefore
> RESOLVED: all four criteria are green on macOS 26 — S1 suppress proven & titlebar-scoped
> (normal scroll intact, felt), S2 live count ✅, S3 AX write ✅, S4 felt ✅; a contact-stream
> use-after-free was found + fixed along the way. One perf item (off-thread band-check cache)
> is carried into M1.** The original "S1–S4 on 14/15/26" requirement is superseded by the
> latest-only scope.

## How it was completed

The gate is resolved on **macOS 26 (latest)** — the only supported target. The probes ran
with both grants live (Accessibility + Input Monitoring) on the built-in trackpad:

```sh
M0_LISTEN=1 M0_TAP=1 M0_AX=1 M0_HAPTIC=1 sh spike/m0/run-matrix.sh
# M0_DWELL_MS=<n> on a suppress run measures the disable threshold
```

macOS 14/15 are out of scope and were not run. If the support policy ever widens, re-run the
matrix on the added OS and fold `build/results/m0-macos-<ver>.jsonl` into the matrix below.

## S1–S4 matrix — macOS 26 (latest; the only supported target)

Legend: ✅ pass · ◐ partial · ✗ fail · — n/a (out of scope).

| Criterion | macOS 26 (supported) | macOS 14 / 15 |
|---|---|---|
| **S1** capture & suppress | ✅ **PROVEN, titlebar-scoped** — 64 events swallowed, live 2-finger feed (919 frames), `Began` seen, **normal scroll intact (felt — pivot trigger NOT fired)**. ⚠️ in-thread band check max ~20.8ms → off-thread cache is a carried-forward M1 task | — out of scope |
| **S2** finger count | ✅ live count — 919 frames in ~12s (~77Hz), maxFingers 2, clean 0/1/2 transitions; enumeration + UAF-fixed startup ✅ | — out of scope |
| **S3** AX locate + act | ✅ move/resize landed (+20pt nudge under cursor, read-back exact, restored) | — out of scope |
| **S4** haptics (background) | ✅ open/actuate/close = kIOReturnSuccess **and felt** (human-confirmed, built-in trackpad) | — out of scope |

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
  where timeouts stop. **14/15:** n/a (out of scope)
- Callback p50/p95/p99/p999/max under the adversarial matrix:
  **macOS 26:** **max 20.8ms** over 547 callbacks (in-thread `CGWindowListCopyWindowInfo` band
  check, no dwell). Only the max is instrumented today — p50/p95/p99 need a percentile sample.
  The max blows the SPEC ≤~1ms budget → the in-thread band check is the latency hazard;
  off-thread geometry cache (SPEC §6.2) is mandatory for M1. **14/15:** n/a (out of scope)
- Contact-stream frame rate: **macOS 26:** 919 frames in ~12s ≈ **77 Hz**. **14/15:** n/a (out of scope)
- Max `swoosh.ax` queue depth under burst (bounded?): ⏳
- End-to-end gesture→window-moved latency (informational, not an SLA): ⏳
- Measurement machine class / lowest-spec target: macOS 26 (the only supported target) = this machine

## Forced go/no-go decisions — 1 resolved, 1 open (2026-05-31)

- **KTD6 — Input Monitoring required? → UNVERIFIED (cheap to close on 26).** On macOS 26 the
  live contact stream works with Input Monitoring **granted** (919 frames @ ~77Hz), but the
  **IM-denied case was never tested**, so whether the stream strictly *requires* IM is unknown.
  (Enumeration without IM is proven; the live frame stream without IM is not.) So `STRATEGY.md
  §5`'s least-privilege "Accessibility-only" goal (origin R39) is **unverified, not disproven**.
  The one remaining check is a ~30-sec test on macOS 26: toggle Input Monitoring **off** and
  re-run `M0_LISTEN=1 build/m0spike fingers` with two fingers — if frames still arrive,
  Accessibility-only holds; if not, accept the second permission. NSEvent Plan B not needed.
  **(2026-05-31: two denied-test attempts both still read `granted` — the grant is pinned to the
  un-relaunched controlling terminal — so the denied condition was never actually measured. Status
  accepted as OPEN: works with IM granted; strictly-required question unresolved. Revisit before v1,
  since `README.md` claims Accessibility-only.)**
- **MTActuator as a 4th private surface? → ACCEPTED.** Felt actuation confirmed the private
  `MTActuator` path is load-bearing, so haptics ship on it. Record the trade-off (4 private
  surfaces vs. degrade) and append `MTActuator` to the `STRATEGY.md §5` ledger / origin R46.

> MTActuator → a `STRATEGY.md §5` edit (4th private surface, confirmed). The Input-Monitoring
> question is the one open runtime check — a 30-sec IM-denied test on macOS 26. Tracked in the plan.

## Pivot triggers (R8)

- S1 unprovable jank-free → **abort** (suppression impossible). **macOS 26: NOT triggered —
  suppression proven titlebar-scoped, normal scroll intact (felt). Latest-only scope — no
  further OS to confirm.**
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

**GO (macOS-26 basis).** Under the 2026-05-31 latest-only scope decision (macOS 14/15 out of
scope), the M0 gate is **resolved**: on macOS 26 all four criteria are green — **S1 suppression
proven and titlebar-scoped (normal scroll intact, felt — pivot trigger NOT fired), S2 live count
✅, S3 AX write ✅, S4 felt ✅.** The hardest existential risk — claim titlebar pans without
breaking normal scroll, no kext — is retired. Two items ride into M1, neither blocking the GO:
(1) the off-thread geometry cache (the in-thread band check's 20.8ms max must come under budget);
(2) the forced decisions — MTActuator 4th surface (accepted → `STRATEGY.md §5`); the
Input-Monitoring-required question (KTD6) is untested, closable by a 30-sec IM-denied test on
macOS 26. **M1 (product scaffolding per SPEC §6) is unblocked.**
