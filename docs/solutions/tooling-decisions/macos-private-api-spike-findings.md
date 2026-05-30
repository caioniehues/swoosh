---
title: macOS private-API surface — verified facts and how to load/build-validate it (M0 spike)
date: 2026-05-30
category: tooling-decisions
module: m0-spike
problem_type: tooling_decision
component: tooling
severity: high
applies_when:
  - Building or extending the M0 de-risk spike (spike/m0/)
  - Starting the M1 engine, which links the same private-API surface
  - A new macOS beta ships and the private-API surface must be re-validated
  - Deciding how to load MultitouchSupport / MTActuator / AX from Swift
tags: [macos, private-api, multitouchsupport, mtactuator, dlopen, swift-spike, de-risk]
---

# macOS private-API surface — verified facts and how to load/build-validate it (M0 spike)

## Context

Swoosh leans on private/undocumented macOS surfaces (`MultitouchSupport.framework`, `MTActuator`, `CGEventTap`, `AXUIElement`, the `"AXFullScreen"` attribute). The M0 de-risk spike (`spike/m0/`) was built and run on **macOS 26.5 / arm64** to retire the "do these even load and resolve on the newest macOS?" risk before any product code. This captures the verified facts and the load/build decisions so M1 and future sessions don't re-derive them. Empirical scope: the **macOS 26 cell only** — 14/15 and the TCC-gated behaviors (live finger count, suppression, AX writes, felt haptics) are pending hardware (`spike/m0/RESULTS.md`).

## Guidance

**Load private frameworks via `dlopen`/`dlsym` — it is mandatory on Apple Silicon, not stylistic.** arm64e pointer authentication (PAC) bus-errors on direct `-framework` linkage or `extern` decls. `dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)` then `dlsym` each symbol and `unsafeBitCast` to a typed `@convention(c)` function pointer.

**Verified on macOS 26.5 (arm64):**
- All **14** required MultitouchSupport + MTActuator symbols resolve (`MTDeviceCreateList`, `MTDeviceCreateDefault`, `MTDeviceCreateFromDeviceID`, `MTDeviceGetDeviceID`, `MTDeviceIsBuiltIn`, `MTRegisterContactFrameCallback[WithRefcon]`, `MTDeviceStart`, `MTDeviceStop`, `MTActuatorCreateFromDeviceID`/`Open`/`Actuate`/`Close`/`IsOpen`).
- `sizeof(MTTouch) == 96` holds — keep this as a runtime drift tripwire; per-field offsets are NOT ABI-stable, so depend only on the contact callback's `numTouches` argument plus the 96-byte total.
- **`MTDeviceGetDeviceID` resolves and returns a valid non-zero ID** — use the official accessor; do NOT use `mactic`'s byte-offset-64 struct hack (it existed because the accessor wasn't resolving in that project).
- `MTDeviceCreateList` enumerates devices (built-in trackpad) with Input Monitoring **denied and no prompt** — enumeration ≠ listening.

**S4 haptics: skip `NSHapticFeedbackManager`, use private `MTActuator`.** The public API is silenced for non-frontmost processes by Apple design (BetterTouchTool's background-daemon snap haptic fails identically). `MTActuatorActuate(ref, actuationID, 0, 0.0, 0.0)`; IDs 1–6 are the safe set (2 = strong click). `IOReturn == 0` is necessary but NOT sufficient — a wrong waveform arg can return success with no felt tap, so a human feeling for it is the real oracle.

**The single-writer/single-reader finger-count hand-off is a relaxed lock-free atomic via a tiny C shim.** `Synchronization.Atomic` is macOS 15+ (collides with the macOS-14 floor); `swift-atomics` needs the SwiftPM manifest the spike forbids. Use `atomic_load_explicit`/`atomic_store_explicit(..., memory_order_relaxed)` in a bridging header; a lock on the realtime tap-thread read would reintroduce the blocking the design avoids.

**Threading invariants (proven in miniature, contract for M1):** the `CGEventTap` callback decides suppress (`return nil`) / pass synchronously from the finger atomic + scroll phase + a fast in-thread `CGWindowList` band check — **never** an AX call (an AX hit-test on the tap thread is the ~500ms FB11586064 stall). AX locate + writes go off-thread on a `swoosh.ax` serial queue. The `.mayBegin` scroll phase is gone since Monterey (FB9724671) — key off `Began`/`Changed` and use the finger count as the discriminant.

**TCC is measured, not assumed.** `SPEC.md §7` / `STRATEGY.md §5` claim "Accessibility only, no Input Monitoring," but multiple sources say MultitouchSupport contact callbacks need Input Monitoring on 14/15. The spike measures it (enumeration works without it; the *contact stream* is the test). If Input Monitoring is required, the least-privilege posture and origin R3/R39 need revising — this is an **open question**, not settled.

## Why This Matters

This retires the project's central technical risk for the 26 cell with concrete evidence rather than assumption, and it saves M1 from re-deriving the ABI, the load pattern, and the dead-ends: it pre-empts the `NSHapticFeedbackManager` rabbit hole, the offset-64 device-ID hack, and a direct-linkage bus error. The 96-byte tripwire and the symbol list also give the macOS-beta canary a cheap, concrete first check.

## When to Apply

- Before writing any code that touches MultitouchSupport / MTActuator / CGEventTap / AX — read this first.
- On every macOS beta: re-run the spike and confirm the 14 symbols still resolve and `MTTouch` is still 96 bytes (drift here is a hard-fail, not a silent wrong answer).
- When deciding atomics / concurrency primitives under the macOS-14 floor.

## Examples

**`swiftc`-direct build with a C bridge (deliberately no SwiftPM for the throwaway spike):**

```sh
swiftc -O -import-objc-header spike/m0/m0-bridge.h spike/m0/*.swift \
  -framework CoreFoundation -framework IOKit -framework ApplicationServices -o build/m0spike
codesign --sign - --force --options runtime \
  --entitlements spike/m0/m0.entitlements build/m0spike   # disable-library-validation, NO app-sandbox
```

**SourceKit gotcha (cost a confusing moment this session):** because the spike is `swiftc`-built with `-import-objc-header` and **no compile database**, SourceKit/LSP emits false `Cannot find type 'MTTouch' / 'DecisionLog' in scope` diagnostics on every file. They are noise — `sh spike/m0/build.sh` is the real check. Do not chase the squiggles.

**Real Swift definite-initialization trap the build caught:** a nested `func sym()` in a class `init?` that referenced `self.handle` (a stored property) failed with "self used before all stored properties are initialized." Fix: close the helper over the **local** `dlopen` handle and assign the stored properties only after the `guard let ... = sym(...)` chain succeeds.

## Related

- Plan: `docs/plans/2026-05-30-001-feat-m0-derisk-spike-plan.md` · Requirements: `docs/brainstorms/2026-05-30-swoosh-product-requirements.md`
- Canon: `SPEC.md §6` (threading), `§7` (finger-count source), `DERISK.md §1` (the spike), `STRATEGY.md §5` (least-privilege, under measurement)
- Results (verdict PENDING): `spike/m0/RESULTS.md`
- Prior art read for this surface: `mactic`, Hammerspoon `libeventtap.m`, Rectangle `AccessibilityElement.swift`, `AXSwift`, HapticKey/MTMR
