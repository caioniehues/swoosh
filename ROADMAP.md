# Swoosh — Roadmap

> Sequencing for the work. What each milestone delivers, what gates it, and where each ideation survivor lands. Decisions: [`STRATEGY.md`](./STRATEGY.md). Design: [`SPEC.md`](./SPEC.md). De-risk gate: [`DERISK.md`](./DERISK.md).
>
> Last updated 2026-05-31 (M0 gate GO; latest-macOS-only). Status: M0 passed; **M1 in progress** — fraction-native snap engine + record/replay fixture harness landed (`swift test` green, replayer wired into CI); the recognizer, divider-drag, haptics, keyboard, settings, and distribution still ahead.

## Sequencing principles

1. **De-risk first.** `M0` (the spike, `DERISK.md §1`) gates everything. No engine, no UI, no packaging until S1–S4 pass on macOS 26 (latest; the only supported target). *(Done — gate **GO**, `spike/m0/RESULTS.md`.)*
2. **The harness is built *with* the engine, not after.** The fixture format and replayer (`DERISK.md §2–3`) land in `M1` so the macOS-beta canary has something to replay from day one.
3. **Feel before breadth.** Match Swish's *loved* mechanics (swipe, divider-drag, haptics) before adding gesture surfaces. A small set that feels native beats a large set that feels janky.
4. **Distribution is not "later."** The install path ships in v0.1.0 (`M6`). It's the self-owned tap, which has no external deadline; notarization is a separate, traction-triggered milestone (see *Distribution* below).

## Milestones

| Milestone | Delivers | Gate |
|---|---|---|
| **M0 — De-risk spike** | Throwaway program proving S1–S4 (capture/suppress, finger-count, AX locate/act, **haptic actuation**) on macOS 26 (`DERISK.md §1`) — **DONE, GO** | ✓ green |
| **M1 — Snap engine + fixture harness** | Fraction/pixel-native engine (`SPEC.md §5`); capture format + headless replayer (`DERISK.md §2–3`) in CI — **engine + harness done; four-layer SwiftPM scaffold + CI replayer landed** | M0 green |
| **M2 — Recognizer + suppression** | Two-finger swipe + hold-grid picker; the suppression strategy hardened against FB9724671 / FB11586064 (`SPEC.md §6.2`) | M1 |
| **M3 — Divider-drag + haptics** | Multi-window divider-drag resize (`SPEC.md §4.3`); ready/done haptic taps (`SPEC.md §4.4`) — the headline feel features | M2 |
| **M4 — Keyboard + restore** | Configurable shortcuts; exit-fullscreen verb; restore ring buffer (`SPEC.md §4.5–4.6`) | M2 |
| **M5 — Settings + onboarding** | SwiftUI settings; Accessibility onboarding + macOS 26 native-tiling conflict prompt (`SPEC.md §8`) | M3, M4 |
| **M6 — Distribution + v0.1.0** | Self-owned Homebrew tap with `xattr` postflight; README install; **static capability manifest + CI assertion** (`STRATEGY.md §5`); `MAINTAINERS` / hand-off note (`STRATEGY.md §6.1`); first tagged release | M5; canary green |

## Post-v1

| Item | Trigger / target | Source |
|---|---|---|
| **BTT / Multitouch coexistence (cooperative mode)** | v1.1 — the highest-intent switcher pool (`SPEC.md §10`) | survivor #8 |
| **Live "what did it touch" inspector** | v1.x — opt-in, hidden by default. *(The static capability manifest + CI assertion itself ships at v1 — M6.)* | survivor #6 |
| **Co-maintainer recruitment / paid convenience build** | Triggered by the §6.1 continuity rule (a 4-week-unfixed beta break, or downloads past the notarize trigger) | `STRATEGY.md §6.1` |
| **Near-miss ghost overlay (discoverability)** | v1.x — solves the #1 docs complaint without docs | survivor #7 |
| **Notarize → central `homebrew/cask`** | **Traction-triggered, not date-triggered** (see *Distribution*) | survivor #4 |
| **Preset gallery + per-app config presets** | v2 — only if community contribution materializes (`CONTRIBUTING.md`) | survivor #5 |
| **v2 surfaces** | Dock / menubar / App-Switcher / Spaces gestures; Magic Mouse; cross-display gestures | `SPEC.md §2` |

## Distribution — the cask cutoff, precisely

There is a common confusion worth stating plainly so it isn't re-litigated:

- **v0.1.0 ships via our own Homebrew tap** with an `xattr -dr com.apple.quarantine` postflight (`STRATEGY.md §4.4`). This path is **$0** and **has no deadline** — the Sept 1 2026 cutoff does **not** affect a self-hosted tap.
- The **Sept 1 2026 cutoff** only governs the *central* `homebrew/cask` repository: after it, unnotarized casks are removed, so the central channel is reachable *only* via the notarized path.
- Therefore **notarization is a discrete later milestone triggered by traction** (enough users that the central-cask discovery channel — ~10.8k installs/month for Rectangle — is worth $99/yr + a CI notarize/staple pipeline), **not** a launch blocker and **not** bound to the September date. The free-to-users build never changes.
- **Bootstrap discovery (notarization-independent).** Because a self-owned tap has near-zero organic discovery, traction can't come *from* distribution — it comes from a "Show HN" / r/macapps launch, the "free Swish" / "Swish alternative" search threads, and `awesome-mac` / `awesome-macos` + GitHub-topic placement. **Concrete trigger:** notarize when GitHub release-asset downloads exceed ~500/month (`STRATEGY.md §4.4`, §7).

## v1 scope cuts (explicit)

Deferred out of v1 to keep the surface tight (`SPEC.md §2`): Dock / menubar / App-Switcher / Spaces gestures, Magic Mouse support, localization, cross-display *gestures*, any scripting/config-DSL surface (the platform identity we declined, `STRATEGY.md §4.2`).
