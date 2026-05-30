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
| **S1** suppress | `M0_TAP=1 build/m0spike suppress` | two-finger pan on a window titlebar | ⚠️ **see caveat below** |

Extra flags:
- `M0_DWELL_MS=<n> build/m0spike suppress` — dwell-sweep: deliberately burns `<n>` ms
  in the callback to **measure** the `kCGEventTapDisabledByTimeout` threshold per OS.
- Run everything in one pass: `M0_LISTEN=1 M0_TAP=1 M0_AX=1 M0_HAPTIC=1 sh spike/m0/run-matrix.sh`
  → logs to `build/results/m0-macos-<ver>.jsonl`.

## ⚠️ Known caveat: S1 won't actually suppress yet

The `suppress` probe and the `fingers` probe are **separate processes with separate
in-memory atomics**, so the tap never sees a live finger count — its finger value
stays `0`, the `fingers == 2` condition never fires, and it installs the tap, logs
never-block timing + scroll phases + the titlebar-band check, but **never swallows
an event**. Running a `fingers` listener "alongside" does **not** help (different
address space).

To test S1 end-to-end, the `MultitouchClient` (S2) and `EventTapProbe` (S1) must run
in the **same process sharing one atomic** — a small combined-probe addition that is
not yet wired. Until then, the `suppress` probe validates *tap install + never-block
timing + phase logging (confirm `Began`, not `MayBegin`) + the band check*, but not
the suppress decision itself.

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
