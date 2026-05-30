# Swoosh — Claude Code project notes

Open-source macOS window snapping + resize via two-finger trackpad gestures on titlebars. MIT, macOS 14+. A free, auditable alternative to Swish.

**Status: M0 de-risk spike in progress.** Planning is split across four canonical docs (see the map below); the brainstorm requirements + M0 plan live in `docs/brainstorms/` and `docs/plans/`. The only code is the **throwaway** M0 spike in `spike/m0/` — build-validated on macOS 26, with the S1–S4 gate pending real 14/15/26 hardware (`spike/m0/RESULTS.md`). No product skeleton (`Package.swift`/`Sources/`) yet.

## Document map — who owns what

| File | Owns | Treat as |
|---|---|---|
| `STRATEGY.md` | The four resolved forks, market thesis, trust/funding posture, success metrics | **Decision-of-record.** Don't relitigate settled forks without new info. |
| `SPEC.md` | Technical design: gesture catalog, fraction-native engine, architecture, threading, suppression | **Technical canon.** Reference by section ("see §6.2 for suppression"). |
| `DERISK.md` | The week-1 spike, the fixture harness, the macOS-beta canary, Plan B triggers | The risk gate. |
| `ROADMAP.md` | Milestone sequencing, v1/v2 split, the distribution-cutoff detail | The plan-of-record for *order*. |

`README.md` is the public front door; `CONTRIBUTING.md` is the contributor on-ramp.

> **Why multiple docs** (this reverses the old "one spec, not many docs" rule): the 2026-05-30 re-plan surfaced genuine *strategic* forks (charter, identity, durability, distribution) that a technical spec is the wrong place to litigate. The split is deliberate and the docs cross-reference each other; keep them consistent rather than merging them back.

## Settled forks (do not relitigate without new information)

- **Charter: Product (grow it).** Free to users forever; adoption is a goal. `STRATEGY.md §4.1`.
- **Identity: Faithful clone, not a platform.** No scripting surface / control socket in v1. `STRATEGY.md §4.2`.
- **Durability: MultitouchSupport load-bearing, NSEvent Plan B.** `STRATEGY.md §4.3`, `SPEC.md §7`.
- **Distribution: self-owned Homebrew tap now ($0); notarize later, traction-triggered.** `STRATEGY.md §4.4`, `ROADMAP.md`.

Still open / revisit-when-relevant: the funding ladder beyond "free + optional sponsors" (`STRATEGY.md §6`); whether the NSEvent path is ever promoted (`DERISK.md §5`).

## Working in this repo

1. **Code is limited to the throwaway M0 spike.** Implementation has begun with the M0 de-risk spike (`spike/m0/`, `swiftc`-built, deliberately **no** SwiftPM — it is *not* the product skeleton, and is deleted once the gate resolves; only `RESULTS.md` survives). Do **not** scaffold the real product (`Package.swift`, `Sources/`, the four-layer tree) until M0 hits S1–S4 on macOS 14/15/26 (`DERISK.md §1`). The user pushed back on premature stubs before — the spike is the only sanctioned code until the gate is green.
2. **Match the contracts when code starts.** The four-layer architecture and threading model (`SPEC.md §6`) and the project layout are contracts. Event-tap callbacks must not block; AX writes go on the `swoosh.ax` serial queue.
3. Reference docs by file + section number; numbering is intended to be stable.

## Implementation philosophy (governs the M0 spike and all code after)

- **De-risk first.** The `M0` spike (`DERISK.md §1`, code in `spike/m0/`) must hit S1–S4 on macOS 14/15/26 before any engine, settings, or release plumbing. *Build-validated on macOS 26; the S1–S4 gate is pending 14/15 + interactive Accessibility/Input-Monitoring grants — see `spike/m0/RESULTS.md`.* If suppression breaks normal scrolling, the project pivots.
- **The hard part is suppression, not snap math.** Any change touching `EventTap` / the gesture recognizer must re-pass the `DERISK.md §1` matrix (the §6 hard rule).
- **Build the fixture harness *with* the engine** (`ROADMAP.md M1`) — the macOS-beta canary depends on it existing early.
- **Private-API caveat.** Private/undocumented surfaces are loaded at runtime, **never** via SPM `.linkedFramework`: `MultitouchSupport.framework` (finger-count, and likely `MTActuator` haptics) via `dlopen`/`dlsym`, plus the undocumented `"AXFullScreen"` attribute for exit-fullscreen. Every such surface must appear in the capability manifest (`STRATEGY.md §5`). The NSEvent Plan B (`SPEC.md §7`) stays specced even after the primary path works.
- **Fraction-native vocabulary.** The snap engine's native unit is a `FractionalRect` (`SPEC.md §5`). `SnapTarget` *is* a Swift `enum`, but a tagged union whose load-bearing case is `.fraction(FractionalRect)`; never replace that native vocabulary with a closed set of named-position cases (leftHalf, topRightQuarter, …) — keeping fractions native is the architectural decision that kills the 3×3 ceiling.

## Out of scope (do not add)

- A scripting platform, control socket, or arbitrary gesture→action binding (declined identity — `STRATEGY.md §4.2`).
- Telemetry. **Ever.** No analytics, no network in the hot path.
- Apple Developer Program / signing / notarization in v1 — deferred, traction-triggered (`ROADMAP.md`).
- Sparkle auto-updates / bespoke updater — updates ride `brew upgrade`.
- Dock / menubar / App-Switcher / Spaces gestures (v2; some require SIP-off scripting additions many users won't accept).
- Older macOS fallbacks below 14.0 unless an issue is filed.

## Tooling

- **`ast-grep` (installed)** — preferred for structural code search and, importantly, for **CI lint rules that enforce SPEC invariants**: AX writes only inside the Layer-4 snap engine (`SPEC.md §6`), `dlopen`/private-SPI loading only inside `MultitouchClient` (`SPEC.md §7`), no network/telemetry in the hot path. ast-grep matches code *shape* and needs no build — usable before there's a compilable project.
- **LSP tool** — for *semantic* questions (true find-references, types, diagnostics, go-to-definition) once the SwiftPM project builds and `sourcekit-lsp` can index it. Caveat: `dlopen`-loaded private frameworks are invisible to the indexer, so ast-grep covers what LSP can't there. Second caveat: the M0 spike is `swiftc`-built with a `-import-objc-header` bridge and **no** compile database, so SourceKit emits false "cannot find type/symbol" diagnostics on it — `sh spike/m0/build.sh` is the real check, not the LSP squiggles.
- **CE tooling** (`/ce-setup`): `gh`, `jq`, `ast-grep`, `vhs`/`silicon`/`ffmpeg` (demo reels via `ce-demo-reel`), `agent-browser` are installed. Machine-local prefs live in `.compound-engineering/config.local.yaml` (gitignored); the committed `config.local.example.yaml` documents the options.

## Repo conventions

- Default branch: `main`.
- Commits: short imperative subject; body explains *why* if non-obvious. Co-author trailer for AI-assisted commits.
- No global git config on this machine — when committing locally, pass author inline:
  `git -c user.name="Caio Niehues" -c user.email="cniehues1@gmail.com" commit ...`
