---
title: Enforce the capability manifest as a CI assertion, not a promise
date: 2026-05-31
category: architecture-patterns
module: CI + capability manifest
problem_type: architecture_pattern
component: tooling
severity: medium
applies_when:
  - "A project's trust pitch depends on auditability of private/undocumented OS surfaces"
  - "A spec declares architectural invariants (layering, no-network) that prose alone cannot keep honest"
  - "You want a new contributor reaching for an undeclared private API to break the build"
tags: [capability-manifest, ci-assertion, private-api, ast-grep, auditability, layering]
---

# Enforce the capability manifest as a CI assertion, not a promise

## Context

Swoosh's entire reason to exist is trust: it is a free, auditable alternative to a closed binary (Swish) for trackpad window snapping. That pitch is only worth something if "we touch private OS surfaces, but only these, and only here" is *verifiable* rather than asserted. The hard surfaces are real — finger-count and haptics come from `dlopen`/`dlsym` of `MultitouchSupport.framework`, and exit-fullscreen plus the Chrome/Electron move-corruption fix use undocumented Accessibility attributes (`STRATEGY §5`, `SPEC §7`, `SPEC §10`).

A `CAPABILITIES.md` file that merely lists those surfaces is a promise: prose drifts, and the code can grow a new `dlsym` or private AX attribute that the manifest never learns about. The pattern here closes that gap by making the manifest a thing CI *checks against the source*, plus build-free structural rules that enforce *where* each surface may appear.

## Guidance

Two complementary mechanisms, both wired into `.github/workflows/ci.yml`:

1. **Manifest-vs-source assertion** — `scripts/check-capabilities.sh` greps `Sources/` for the two private-surface shapes the code uses, then fails if any token is missing from `CAPABILITIES.md`:
   - `dlsym`'d symbols, matched as the call shape `sym("NAME")` via `grep -rhoE 'sym\("[A-Za-z0-9_]+"\)'`, with `NAME` then pulled out by a `sed -E` substitution.
   - Private AX attributes, matched as the literals `grep -rhoE '"AX(FullScreen|EnhancedUserInterface)"'`.

   For every extracted token it runs `grep -q "$token" "$MANIFEST"` and sets `fail=1` on a miss, printing `UNDECLARED: '<token>' is used in Sources/ but is not declared in CAPABILITIES.md`. The script is `set -eu` and ends with `exit $fail`, so a miss makes CI go red.

2. **Layering rules (build-free, structural)** — three `ast-grep` rules under `.ast-grep/rules/`, run via `ast-grep scan` (config `sgconfig.yml` points `ruleDirs` at `.ast-grep/rules`), all `severity: error`:
   - `dlopen-only-in-multitouchclient` — `pattern: dlopen($$$)` over `Sources/**/*.swift`, ignoring `Sources/SwooshKit/MultitouchClient.swift`. Private-framework loading lives in exactly one file.
   - `ax-write-only-in-layer4` — `pattern: AXUIElementSetAttributeValue($$$)`, ignoring `Sources/SwooshKit/SnapApplier.swift` (Layer 4). An AX write near the tap thread is the FB11586064 stall this architecture exists to avoid.
   - `no-network-in-sources` — `pattern: URLSession` over `Sources/**/*.swift`, no ignores. No telemetry, no network, ever.

The CI `lint` job runs `ast-grep scan` then `sh scripts/check-capabilities.sh`. The assertion is **non-vacuous**: it currently resolves 10 `dlsym`'d symbols (six finger-count + four `MTActuator` haptics) and 2 private AX attributes, all already declared in the manifest — so it is checking real tokens, not an empty set.

Two design notes that make this robust:
- The manifest deliberately omits public APIs (`CGEventTap`, public `AXUIElement` attributes, `CGWindowList`, `NSScreen`, `UserDefaults`) — they need no trust declaration, so listing them would dilute the signal.
- The grep keys on call/literal *shape* (`sym("...")`, `"AXFullScreen"`), not on a hand-maintained symbol list, so the check discovers new private usage automatically instead of needing someone to remember to extend the checker.

## Why This Matters

A closed binary asks you to trust the vendor. Swoosh's counter-offer is that you don't have to: the full private-surface inventory is in one committed file, and CI guarantees the code can't quietly outgrow it. The moment a contributor adds a new `sym("MTSomethingNew")` or a third private AX attribute without updating `CAPABILITIES.md`, the build fails — the manifest can't silently fall out of date. Likewise, a `dlopen` outside `MultitouchClient.swift`, an `AXUIElementSetAttributeValue` outside `SnapApplier.swift`, or any `URLSession` anywhere in `Sources/` breaks the build. Trust becomes a property CI enforces rather than a claim the README makes.

A note on scope: this CI machinery verifies the *static* trust contract — which private surfaces exist and where they live. It does **not** verify Swoosh's live trackpad/AX behavior; that is confirmed only on real hardware by a user-run check (`spike/m0/RESULTS.md`). The CI build/test job covers pure logic plus the fixture replayer; the lint job covers these capability/layering assertions. The two are complementary: hardware proves it works, CI proves it stays auditable.

## When to Apply

- Your product's value proposition is auditability or trust, and you depend on private/undocumented OS surfaces.
- You have a spec with hard architectural invariants (single-file confinement, layer boundaries, no-network) that you want enforced rather than documented.
- You want the failure mode to be "the build breaks" instead of "someone notices in review six months later."

Skip or adapt if: there are no private surfaces to inventory, or the invariant is too subtle for a shape-based grep / AST pattern (then reach for a real semantic check). Note `dlopen`-loaded private frameworks are invisible to the LSP indexer, which is exactly why the shape-based `ast-grep`/grep approach is used here — it needs no build and no symbol resolution.

## Examples

A contributor adds finger-velocity support and writes `let p = sym("MTDeviceGetSensorSurfaceDimensions")` in `MultitouchClient.swift`, but forgets `CAPABILITIES.md`. The `lint` job's capability check prints:

```
UNDECLARED: 'MTDeviceGetSensorSurfaceDimensions' is used in Sources/ but is not declared in CAPABILITIES.md
```

Exit non-zero → red build. Fix is to add a row under "Private frameworks" in `CAPABILITIES.md`.

A contributor moves an AX write into a Layer-2 file to "save a hop". `ast-grep scan` fires `ax-write-only-in-layer4` (severity error) with the SPEC §6 message about the FB11586064 stall. The green-CI path is to keep `AXUIElementSetAttributeValue` inside `SnapApplier.swift`.

The happy path prints, from `check-capabilities.sh`:

```
capability check OK — every private surface in the code is declared in CAPABILITIES.md
  symbols:  MTActuatorActuate MTActuatorClose MTActuatorCreateFromDeviceID MTActuatorOpen ...
  ax attrs: AXEnhancedUserInterface AXFullScreen
```

## Related

- `docs/solutions/tooling-decisions/macos-private-api-spike-findings.md` — the M0-spike findings; it names the capability manifest as the destination, this doc is its CI enforcement.
- `CAPABILITIES.md` — the manifest itself (trust contract, `STRATEGY §5`); lists the 10 symbols + 2 AX attributes + entitlements + TCC permissions.
- `scripts/check-capabilities.sh` — the manifest-vs-source assertion.
- `.ast-grep/rules/dlopen-only-in-multitouchclient.yml`, `ax-write-only-in-layer4.yml`, `no-network-in-sources.yml` — the layering rules.
- `sgconfig.yml` — `ast-grep` project config (`ruleDirs`).
- `.github/workflows/ci.yml` — wires both into CI (`lint` job runs `ast-grep scan` then the capability script; `build-test` job is the fixture-replayer canary, `DERISK §3`).
- `SPEC §6` (four-layer architecture / threading), `SPEC §7` (private SPI / NSEvent Plan B), `SPEC §10` (`AXEnhancedUserInterface` / KTD7).
