# Swoosh — Fresh-Planning Ideation

> Date: 2026-05-30 · Status: grounding for collaborative re-plan · Method: 12-agent workflow (4 web-research + 6 ideation frames + adversarial critique + synthesis), 43 raw ideas → 8 survivors.
> The prior `SPEC.md` / `CLAUDE.md` are treated here as **prior art to challenge, not constraints** (per user direction to re-plan from scratch).

---

## Competitive brief — where Swoosh fits, and the white space

**The uncontested slot is real and precise.** Mapping the macOS window-manager market on two axes (input model × license) leaves exactly one empty cell: *free + open-source + trackpad-gesture-primary + titlebar-swipe*.

- Free / keyboard-or-tiling quadrant is owned: Rectangle (~29k ★), AeroSpace (~21k ★), Amethyst (~16k ★), Hammerspoon (~15.5k ★), Loop (~10.8k ★).
- Paid / gesture quadrant is owned: Swish ($16), BetterTouchTool (~$22), Multitouch (~$16).
- **Free / gesture cell has exactly one occupant — Penc (1.2k ★, abandoned since July 2021.)** That is the Rectangle-vs-Magnet opening, ~7 years later, in the gesture niche.

**Why the slot stayed empty: a three-layer private-API integration.** `CGEventTap` (scroll suppression) + `MultitouchSupport.framework` (undocumented finger-count SPI) + `AXUIElement` titlebar hit-testing. Confirmed load-bearing hazards: FB9724671 (`.mayBegin` scroll phase vanished in Monterey — hit Swish directly) and FB11586064 (AX hit-test can block scroll up to 500ms). Genuine moat *and* genuine fragility — it's why Penc went dormant and no active OSS clone exists.

**Swish's #1 complaint is its #1 opening.** Custom window sizes are the single most-cited unmet need — especially ultrawide users wanting 4–5 column layouts. Swish caps at 3×3 and defers custom sizes to an unshipped "Swish 2." A fraction/pixel-native engine ships day one what the paid incumbent only promised.

**Do not bury what makes Swish *loved*** (the idea pool almost ignored both; any like-for-like reviewer tests them first):
- **Divider-drag multi-window resize** — the most-cited *unique* Swish feature vs Rectangle/Moom ("the single killer feature," per HN). Old SPEC §4.4 commits to it; it must be foregrounded, not treated as plumbing.
- **Haptic threshold feedback** — the "ready tap" at threshold + completion tap; a top-4 praise item central to the "feels native / invisible infrastructure" quality (the #1 praise). It belongs in the gesture spec.

**The trust wedge is load-bearing but not sufficient alone.** Rectangle led positioning with security/auditability and notarization, *never price*; Loop's brief sponsor-only-settings move triggered immediate backlash (open source is a "load-bearing promise" for Accessibility-hungry tools); Karabiner earns driver-level trust purely because the code is auditable. But **every competitor in the niche is already MIT — open source is table stakes**, so auditability must be made *experienceable* (runtime ledger / CI-asserted capability manifest / reproducible builds) to differentiate.

**Two clocks tick inside the planning horizon (today = 2026-05-30):**
- **Sept 1 2026** — Homebrew/cask removes all unnotarized casks; `--no-quarantine` already gone (Homebrew 5.0, Nov 2025). The old SPEC's "defer signing to v1.0 if anyone cares" is now untenable: either notarize ($99/yr) or self-host a tap with `xattr` postflight (the AeroSpace model). Homebrew drove ~10.8k installs/month for Rectangle — the highest-ROI channel for this audience.
- **The existential threat is Apple, not Swish.** macOS 15+ ships free, built-in drag-to-edge tiling. Once "free" is matched by the OS, the surviving differentiators are *gesture feel* (titlebar swipe + divider-drag + haptics, which native tiling doesn't do), *auditability*, and *configurability beyond 3×3*. The plan must answer **"why use Swoosh once macOS snaps windows for free?"** — that is the strategic spine, not a footnote.

---

## Ranked directions (survivors)

| # | Direction | Axis | One-line |
|---|---|---|---|
| 1 | **Fraction/pixel-native snap engine** | beyond-swish | Resolve any fraction/pixel rect, not a fixed 3×3 enum. Ultrawide N-column falls out free; ships what "Swish 2" only promised. |
| 2 | **Record-and-replay gesture fixture harness** | trust | Capture real multitouch + scroll + AX streams to disk; headless replay in CI. Every bug → permanent regression test; beta validation → "replay corpus, diff decisions." Highest-compounding. |
| 3 | **Exit-fullscreen + reversible undo as first-class gestures** | gesture | Fix two daily dead-ends Swish leaves open (no exit-fullscreen gesture; awkward recovery). Restore ring-buffer. Cheap, high-frequency, table-stakes polish. |
| 4 | **Distribution decided now (Sept 1 2026 cutoff)** | distribution | Notarize ($99/yr → homebrew/cask) **or** self-host tap w/ xattr postflight. A forced decision, not a feature. |
| 5 | **Config-as-code (plain-text source of truth, GUI is a view)** | beyond-swish | TOML for gestures/layouts/per-app/presets; hot-reload. Capability *and* contributor flywheel. Leans developer/ricer audience. |
| 6 | **Runtime auditability: CI-asserted capability manifest + live "what did it touch" inspector** | trust | Machine-readable manifest of private APIs/entitlements, CI-enforced; live inspector of AX reads/writes + suppress/pass decisions. "Watch what it does, live." The one differentiator that survives Apple matching "free." |
| 7 | **In-context discoverability: near-miss ghost overlay, no tutorial** | gesture | On an almost-correct gesture, show what *would* have snapped where; self-disables after N successes. Solves the #1 docs complaint without docs. |
| 8 | **BetterTouchTool coexistence as a designed-in guarantee** | gesture | Detect BTT/Multitouch at launch; offer cooperative listen-only mode. Turns a notorious trackpad-freeze into "plays nice." Targets the highest-intent switcher pool. |

### Notable rejections
- **Permissionless / zero-Accessibility mode** — self-contradictory; titlebar gestures need AX twice (hit-test + suppression).
- **Antifragile chaos-testing (SRE framing)** — decorative label on the beta-canary; folded into #2.
- **Fighting-game training sandbox** — heavy subsystem for a tool whose whole point is being invisible; #7 hits the same goal cheaply.
- **F-Droid store + Sparkle delta updates** — fantasy infra; contradicts "updates ride `brew upgrade`," reintroduces network dependency.
- **Reproducible-builds as a headline** — reproducible codesigned Swift `.app` bundles are research-grade, not "one command." Survives as a *future* trust goal under #6, cost named honestly.
- **Control socket / CLI / headless daemon** — strong as a *platform* bet, but an identity decision (see fork 2), not a v1 clone feature.

---

## Strategic forks (must decide before drafting files)

1. **Charter** — personal open-source project vs product meant to grow. The grading lens for everything else; gates the funding question.
2. **Identity** — faithful free Swish clone vs programmable trackpad-gesture platform vs clone-first/platform-ready-architecture.
3. **Durability** — `MultitouchSupport` load-bearing (precision, fragile) vs public NSEvent path as default (resilient, less precise).
4. **Distribution** — notarize ($99/yr, homebrew/cask) vs self-owned tap (xattr postflight) vs build-from-source formula. Forced by the Sept 1 2026 cutoff; downstream of Charter.

---

## Proposed new file structure (replacing single-SPEC)

| File | Purpose |
|---|---|
| `STRATEGY.md` | The four resolved forks + white-space thesis + the "why over native tiling" answer + trust/funding/metrics. *(Departs from old "one spec, not many docs" rule — justified by genuine strategic forks SPEC is the wrong place to litigate.)* |
| `SPEC.md` | Technical canon, **rewritten**: gesture catalog led by titlebar-swipe + divider-drag + haptics; fraction/pixel-native engine (enum torn out); 4-layer architecture + threading + suppression; exit-fullscreen/restore; permissions; edge cases. |
| `DERISK.md` | Week-1 spike pass/fail criteria + the fixture-format & headless-replayer design + macOS-beta canary plan + Plan-B trigger. |
| `ROADMAP.md` | Milestones gated on the spike; harness built alongside engine; distribution scheduled *before* Sept 2026; v1/v2 split conditional on forks. |
| `CLAUDE.md` | Updated AI-session rules for the multi-file structure; settled-vs-open forks; keep de-risk-first, suppression-is-the-hard-part, dlsym caveat, no-telemetry, local author trailer. |
| `README.md` | Public front door; install reflects chosen distribution branch; auditability statement. |
| `CONTRIBUTING.md` | **Only if charter=product or identity=platform** — fixture/preset/compat-pack on-ramps; capability-manifest rule; license choice. |
