---
title: macOS private-API surface — verified facts and how to load/build-validate it (M0 spike)
date: 2026-05-30
last_refreshed: 2026-05-31
category: tooling-decisions
module: private-API surface (SwooshKit/MultitouchClient)
problem_type: tooling_decision
component: tooling
severity: high
applies_when:
  - Working on SwooshKit/MultitouchClient or any MultitouchSupport / MTActuator / AX surface
  - A new macOS beta ships and the private-API surface must be re-validated
  - Deciding how to load MultitouchSupport / MTActuator / AX from Swift (always dlopen, never link)
tags: [macos, private-api, multitouchsupport, mtactuator, dlopen, accessibility, de-risk]
---

# macOS private-API surface — verified facts and how to load/build-validate it (M0 spike)

## Context

Swoosh leans on private/undocumented macOS surfaces (`MultitouchSupport.framework`, `MTActuator`, `CGEventTap`, `AXUIElement`, the `"AXFullScreen"` and `"AXEnhancedUserInterface"` attributes). The M0 de-risk spike (since retired — only `spike/m0/RESULTS.md` survives) was built and run on **macOS 26.5 / arm64** to retire the "do these even load and resolve on the newest macOS?" risk before any product code. This captures the verified facts and the load/build decisions; M1 ported them into the real product (`Sources/SwooshKit/MultitouchClient.swift`).

**Status (refreshed 2026-05-31): the M0 gate resolved GO.** S1–S4 are green on macOS 26 — suppression proven titlebar-scoped (normal scroll intact), live finger count, AX move/resize, and *felt* haptics (`spike/m0/RESULTS.md`). Swoosh is now **latest-macOS-only** (macOS 26; 14/15 out of scope as of 2026-05-31), so the old "14/15 pending" caveat no longer applies. One TCC question stays open: whether the live contact *stream* strictly needs Input Monitoring on 26 (the IM-denied case — KTD6 — is untested).

## Guidance

**Load private frameworks via `dlopen`/`dlsym` — it is mandatory on Apple Silicon, not stylistic.** arm64e pointer authentication (PAC) bus-errors on direct `-framework` linkage or `extern` decls. `dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)` then `dlsym` each symbol and `unsafeBitCast` to a typed `@convention(c)` function pointer.

**Verified on macOS 26.5 (arm64):**
- All **14** required MultitouchSupport + MTActuator symbols resolve (`MTDeviceCreateList`, `MTDeviceCreateDefault`, `MTDeviceCreateFromDeviceID`, `MTDeviceGetDeviceID`, `MTDeviceIsBuiltIn`, `MTRegisterContactFrameCallback[WithRefcon]`, `MTDeviceStart`, `MTDeviceStop`, `MTActuatorCreateFromDeviceID`/`Open`/`Actuate`/`Close`/`IsOpen`).
- `sizeof(MTTouch) == 96` holds — keep this as a runtime drift tripwire; per-field offsets are NOT ABI-stable, so depend only on the contact callback's `numTouches` argument plus the 96-byte total.
- **`MTDeviceGetDeviceID` resolves and returns a valid non-zero ID** — use the official accessor; do NOT use `mactic`'s byte-offset-64 struct hack (it existed because the accessor wasn't resolving in that project).
- `MTDeviceCreateList` enumerates devices (built-in trackpad) with Input Monitoring **denied and no prompt** — enumeration ≠ listening.

**S4 haptics: skip `NSHapticFeedbackManager`, use private `MTActuator`.** The public API is silenced for non-frontmost processes by Apple design (BetterTouchTool's background-daemon snap haptic fails identically). `MTActuatorActuate(ref, actuationID, 0, 0.0, 0.0)`; IDs 1–6 are the safe set (2 = strong click). `IOReturn == 0` is necessary but NOT sufficient — a wrong waveform arg can return success with no felt tap, so a human feeling for it is the real oracle.

**The single-writer/single-reader finger-count hand-off is a relaxed lock-free atomic.** A lock on the realtime tap-thread read would reintroduce the blocking the design avoids. The *spike* used a tiny C-shim (`atomic_load/store_explicit(..., memory_order_relaxed)` in a bridging header) because it had to clear the macOS-14 floor without a SwiftPM manifest. **The product no longer does:** latest-macOS-only (macOS 26) makes `Synchronization.Atomic` available, so `Sources/SwooshKit/MultitouchClient.swift` uses `Atomic<Int32>` with `.relaxed` ordering (single MT-callback writer, single tap-thread reader) and the C-shim is retired.

**Threading invariants (proven in miniature, contract for M1):** the `CGEventTap` callback decides suppress (`return nil`) / pass synchronously from the finger atomic + scroll phase + a fast in-thread `CGWindowList` band check — **never** an AX call (an AX hit-test on the tap thread is the ~500ms FB11586064 stall). AX locate + writes go off-thread on a `swoosh.ax` serial queue. The `.mayBegin` scroll phase is gone since Monterey (FB9724671) — key off `Began`/`Changed` and use the finger count as the discriminant.

**TCC is measured, not assumed.** `SPEC.md §7` / `STRATEGY.md §5` aim for "Accessibility only, no Input Monitoring." Enumeration provably works without Input Monitoring (no prompt). The *contact stream* is the real test: on macOS 26 it works with Input Monitoring **granted** (live count confirmed); whether it strictly **requires** IM is still untested (the IM-denied run — KTD6 — was never captured). If IM turns out required, the least-privilege posture and origin R3/R39 need revising. (14/15 are out of scope now, so the old "needs IM on 14/15" reports no longer bear on this.)

## Why This Matters

This retires the project's central technical risk for the 26 cell with concrete evidence rather than assumption, and it saves M1 from re-deriving the ABI, the load pattern, and the dead-ends: it pre-empts the `NSHapticFeedbackManager` rabbit hole, the offset-64 device-ID hack, and a direct-linkage bus error. The 96-byte tripwire and the symbol list also give the macOS-beta canary a cheap, concrete first check.

## When to Apply

- Before writing any code that touches MultitouchSupport / MTActuator / CGEventTap / AX — read this first.
- On every macOS beta: re-run the spike and confirm the 14 symbols still resolve and `MTTouch` is still 96 bytes (drift here is a hard-fail, not a silent wrong answer).
- When deciding atomics / concurrency primitives — latest-macOS-only now, so `Synchronization.Atomic` is available and no C-shim is needed.

## Examples

**Build (product, SwiftPM):** the product is a normal SwiftPM package — `swift build` / `swift test`. The throwaway spike's `swiftc`-direct recipe (`-import-objc-header m0-bridge.h`, ad-hoc `codesign` with `disable-library-validation` + NO app-sandbox) is retired with the spike; it lives in git history (commit `1549b29`) if that entitlements posture is ever needed as a reference. The entitlement still matters: any process that `dlopen`s the private framework needs `com.apple.security.cs.disable-library-validation` and no app-sandbox (`CAPABILITIES.md`).

**SourceKit / LSP:** the spike's `swiftc`-built, no-compile-database setup made SourceKit emit false `Cannot find type … in scope` diagnostics — that was spike-only and is gone now the product is SwiftPM (`sourcekit-lsp` indexes it cleanly). The caveat that persists: `dlopen`-loaded private symbols are invisible to the indexer, so `ast-grep` (not the LSP) is what covers the `MultitouchClient` surface.

**Real Swift definite-initialization trap the build caught:** a nested `func sym()` in a class `init?` that referenced `self.handle` (a stored property) failed with "self used before all stored properties are initialized." Fix: close the helper over the **local** `dlopen` handle and assign the stored properties only after the `guard let ... = sym(...)` chain succeeds.

## Related

- Plan: `docs/plans/2026-05-30-001-feat-m0-derisk-spike-plan.md` · Requirements: `docs/brainstorms/2026-05-30-swoosh-product-requirements.md`
- Canon: `SPEC.md §6` (threading), `§7` (finger-count source), `DERISK.md §1` (the spike), `STRATEGY.md §5` (least-privilege, under measurement)
- Results (verdict **GO**): `spike/m0/RESULTS.md`
- M1 learnings that build on this surface: `docs/solutions/architecture-patterns/pure-decision-seam-for-testable-system-code.md` (the threading invariants above, made CI-testable); `docs/solutions/architecture-patterns/capability-manifest-as-ci-assertion.md` (this private surface, declared + CI-enforced); `docs/solutions/tooling-decisions/swiftpm-macos-build-gotchas.md` (the SwiftPM build path — distinct from the spike's swiftc recipe, don't conflate)
- Product code embodying these findings: `Sources/SwooshKit/MultitouchClient.swift` (dlopen + `Synchronization.Atomic`); `CAPABILITIES.md` (the private-surface ledger)
- Prior art read for this surface: `mactic`, Hammerspoon `libeventtap.m`, Rectangle `AccessibilityElement.swift`, `AXSwift`, HapticKey/MTMR
