# M0 De-Risk Spike — RESULTS (go / no-go)

> The durable artifact that outlives the spike. It is the input to the M1 go
> decision. Plan: `docs/plans/2026-05-30-001-feat-m0-derisk-spike-plan.md`.
>
> **Status: INTERIM — macOS 26 partially exercised; 14/15 and all TCC-gated +
> haptic-felt cells pending real hardware.** Do not read any "go" into this yet.

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
| **S1** capture & suppress | ⏳ | ⏳ | ◐ build-validated; active-tap suppression ⏳ (needs Accessibility + trackpad) |
| **S2** finger count | ⏳ | ⏳ | ◐ enumeration ✅ (built-in device, valid ID); live count ⏳ (needs Input Monitoring + touch) |
| **S3** AX locate + act | ⏳ | ⏳ | ◐ build-validated; move/resize ⏳ (needs Accessibility) |
| **S4** haptics (background) | ⏳ | ⏳ | ◐ symbols + device-ID ✅; felt actuation ⏳ (needs M0_HAPTIC=1 + a human; external trackpad absent) |

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

## Numeric performance baseline (R9) — PENDING

Filled from the hardware runs; none are measurable without the active tap + load:

- Measured per-OS `kCGEventTapDisabledByTimeout` threshold (dwell-sweep, N runs + variance): ⏳
- Callback p50/p95/p99/p999/max under the adversarial matrix: ⏳
- Max `swoosh.ax` queue depth under burst (bounded?): ⏳
- End-to-end gesture→window-moved latency (informational, not an SLA): ⏳
- Measurement machine class / lowest-spec target: macOS 26 cell = this machine; 14/15 ⏳

## Forced go/no-go decisions — PENDING measurement

These do **not** auto-resolve to "go"; each needs a recorded decision once measured:

- **KTD6 — Input Monitoring required?** Seed on 26: `IOHIDCheckAccess(listenEvent)`
  currently `denied`; whether contact frames arrive *only* with Input Monitoring
  granted is the `M0_LISTEN=1` measurement. **If required on any OS:** record the
  strategy resolution (accept the second permission and revise `STRATEGY.md §5` /
  origin R39, **or** invoke the NSEvent Plan B to hold least-privilege) before M1.
- **MTActuator as a 4th private surface?** Symbols resolve; if felt actuation
  confirms the private path is load-bearing, record the trade-off (ship haptics at
  4 private surfaces vs. degrade to hold the 3-surface auditability story) and
  append `MTActuator` to the `STRATEGY.md §5` ledger / origin R46 — in the **same
  commit** that finalizes this file.

## Pivot triggers (R8)

- S1 unprovable jank-free → **abort** (suppression impossible).
- S2 unreliable / struct drift → **NSEvent Plan B** for finger-count.
- S4 unprovable on the private path → **ship without haptics** (degrade).

## Verdict

**PENDING.** macOS 26's build/load/struct/atomic/enumeration foundation is green;
the empirical S1–S4 gate (suppression, live finger count, AX writes, felt haptics)
across 14/15/26 with an external trackpad is the remaining, human-run work.
