# M0 spike — manual test runbook

How to run the S1–S4 de-risk probes on real hardware and fold the results into
`RESULTS.md`. The gate resolves only when S1–S4 are green on **macOS 14, 15, and
26**, ideally with an external Magic Trackpad. Run this on each OS.

Plan: [`docs/plans/2026-05-30-001-feat-m0-derisk-spike-plan.md`](../../docs/plans/2026-05-30-001-feat-m0-derisk-spike-plan.md) · Results: [`RESULTS.md`](./RESULTS.md)

---

## 1. Build (once)

```sh
cd <repo-root>            # e.g. /Users/caioniehues/Code/swoosh
sh spike/m0/build.sh      # → build/m0spike  (gitignored, ad-hoc signed)
```

The binary is `build/m0spike` (absolute: `<repo-root>/build/m0spike`).

> **Re-sign churn:** every `build.sh` re-signs the binary with a fresh ad-hoc
> identity, which can silently invalidate a prior permission grant. Don't rebuild
> between test runs — and if you do, re-toggle the grants (step 2). Each probe
> prints its own `tcc.before` line so you can see the live permission state.

## 2. Grant permissions (System Settings → Privacy & Security)

Two permissions are needed: **Accessibility** (active event tap + AX writes) and
**Input Monitoring** (MultitouchSupport contact stream).

macOS TCC is finicky about bare CLI tools — it often attributes the permission to
the **controlling terminal**, not the binary. So the reliable path:

1. **Grant your terminal app** (Terminal / iTerm / Ghostty — whichever you run the
   commands in) **both** Accessibility *and* Input Monitoring.
2. **Fully quit and reopen** that terminal (TCC changes apply on relaunch).
3. *(Optional belt-and-suspenders)* also add the binary directly: in each pane
   click **+**, press **⌘⇧G**, paste `<repo-root>/build/m0spike`, enable it.

If a probe logs `accessibility:false` or `inputMonitoring:denied`, the grant
didn't take — fix the terminal grant and restart the terminal.

## 3. Run the probes

Run from the repo root. Each probe prints JSONL to stdout and appends to
`$TMPDIR/swoosh-m0.jsonl` (override with `M0_LOG=/path/to/log.jsonl`).

| Criterion | Command | Do physically | Pass looks like |
|---|---|---|---|
| sanity | `build/m0spike scaffold` | — | `scaffold.result … pass:true` (no grant needed) |
| **S2** finger count | `M0_LISTEN=1 build/m0spike fingers` | rest **two fingers** on the trackpad during the ~6s window | `mt.count … count:2`, `fingers.result … framesSeen` > 0 |
| **S3** AX move/resize | hover the cursor over a real window (Finder), then `M0_AX=1 build/m0spike axact` | leave the cursor over the window | the window nudges 20px and back; `ax.write … landed:true` |
| **S4** haptics | `M0_HAPTIC=1 build/m0spike haptics` | **feel** the trackpad | you feel a click; `haptic.actuate … ok:true` — the felt tap is the real oracle, `IOReturn:0` alone is not enough. Test on an **external** Magic Trackpad too (open hazard). |
| **S1** suppress | `M0_TAP=1 M0_LISTEN=1 build/m0spike suppress` | rest **two fingers** and pan a window titlebar | `tap.summary … suppressed` > 0 **and** normal two-finger scroll elsewhere still works |

Extra flags:
- `M0_DWELL_MS=<n> build/m0spike suppress` — dwell-sweep: deliberately burns `<n>` ms
  in the callback to **measure** the `kCGEventTapDisabledByTimeout` threshold per OS.
- `M0_SECONDS=<n> … suppress` — widen the capture window (default 8s) so you have time
  to rest two fingers *and* pan a titlebar in the combined run.
- Run everything in one pass: `M0_LISTEN=1 M0_TAP=1 M0_AX=1 M0_HAPTIC=1 sh spike/m0/run-matrix.sh`
  → logs to `build/results/m0-macos-<ver>.jsonl`. Because both `M0_TAP` and `M0_LISTEN`
  are set, the matrix's `suppress` step runs in **combined mode** automatically.

## S1 combined probe (the suppress decision is now testable)

`M0_TAP=1 M0_LISTEN=1 build/m0spike suppress` starts the MultitouchSupport contact
stream **and** the active tap in **one process sharing the single KTD8 atomic**, so
the tap reads a live finger count. With both env vars set, `fingers == 2` can actually
fire and the event is swallowed — this is the real S1 test.

> Earlier this was impossible: `suppress` and `fingers` were separate processes with
> separate atomics, so the tap's finger value stayed `0` and it never swallowed an
> event. That's resolved — the wiring lives in `runSuppress()` (`main.swift`).

How to read the result:
- **Suppression happened** if `tap.summary … suppressed` > 0 after you pan a titlebar
  with two fingers, and `liveMaxFingers` in `suppress.result` reached `2`.
- **The hard half is the negative test:** while the probe runs, two-finger scroll a
  *normal* window body (not a titlebar) — it must scroll normally. If suppression
  bleeds into ordinary scrolling, S1 **fails** (DERISK §1: "breaks normal scroll → pivot").
- **Phase sanity:** `firstPhases` should contain `Began` (1), not only `MayBegin`
  (128) — the FB9724671 check.

Without `M0_LISTEN=1`, `suppress` still runs the dry tap-install + never-block timing
+ band check (finger count stays 0, nothing suppressed) — useful for the dwell-sweep.

## 4. Record the results

Fold each run's log into the matrix in [`RESULTS.md`](./RESULTS.md):

- S1–S4 × {14, 15, 26} cells: ✅ pass / ◐ partial / ✗ fail.
- Numeric baseline (per OS): measured disable threshold, callback tail latencies,
  bounded queue depth, machine class.
- The two **forced decisions**: if **Input Monitoring is required** for the finger
  stream → record the strategy resolution (revise `STRATEGY.md §5` / R39, or take the
  NSEvent Plan B); if **MTActuator is felt** → record the 4th-private-surface trade-off.

A criterion is green for the gate only when it passes on **all three** OSes. The
verdict stays **PENDING** until then; do not start M1 on a partial gate.
