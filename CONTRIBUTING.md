# Contributing to Swoosh

Swoosh is an early product-stage open-source project ([`STRATEGY.md §4.1`](./STRATEGY.md)). Contributions are welcome — and deliberately laddered so you can help without writing Swift.

> **Status: spec only.** There's no build yet, so today the useful contributions are design feedback (open a discussion) and review of the planning docs. The on-ramps below describe how contribution will work once code lands; they're documented now so the architecture is built to support them.

## Before you start

- Read [`STRATEGY.md`](./STRATEGY.md) (the settled decisions) and [`SPEC.md`](./SPEC.md) (the design). The four strategic forks — charter, identity, durability, distribution — are **settled**; please don't open PRs that relitigate them without new information.
- Be aware of the firm non-goals: **no telemetry, ever**; **no scripting platform / control socket** (Swoosh is a faithful clone, not "Hammerspoon for the trackpad" — `STRATEGY.md §4.2`).

## Contribution ladder (lowest bar first)

### 1. Design / docs / planning feedback *(available now — no app needed)*

The project is pre-implementation, so the most useful contribution *today* is review of the planning docs (`STRATEGY.md`, `SPEC.md`, `DERISK.md`) and design discussion — open a GitHub discussion or issue. This rung exists before any adoption, on purpose: the contributor flywheel can't bootstrap on a community that doesn't exist yet.

### 2. Submit a gesture fixture *(no Swift required)*

The highest-leverage code-adjacent contribution. When a gesture misbehaves, flip on Swoosh's **capture mode** (a hidden runtime toggle in the *released* app — no toolchain needed) to record what each layer saw (the multitouch stream, the scroll stream, the fast-geometry decision, the AX result, and Swoosh's verdict) into a single fixture file, and attach it to your bug report. We turn it into a permanent regression test via the headless replayer. See [`DERISK.md §2`](./DERISK.md#2-the-fixture-format-record).

This is what makes the project survivable: every reported bug becomes a test that runs on every PR and every macOS beta. The maintainer seeds the initial corpus from daily use, so it exists before external users arrive.

### 3. Code

Standard PRs. Two project-specific rules:

- **The de-risk hard rule.** Any change touching `EventTap` or the gesture recognizer must re-pass the [`DERISK.md §1`](./DERISK.md#1-the-week-1-spike-go--no-go-gate) spike matrix (or its replayer equivalent) before merge. Suppression and finger-count break invisibly; they get the strictest gate.
- **The capability-manifest rule.** The capability manifest ships at v1 ([`ROADMAP.md`](./ROADMAP.md) M6). A PR that widens the app's reach — a new private API touched, a new entitlement requested, anything that reads more of the system — must update the manifest, or CI fails. This keeps the "auditable" promise (`STRATEGY.md §5`) machine-enforced rather than aspirational.

### Later (v2): config / layout presets

Shareable custom layouts (e.g. ultrawide N-column) and per-app overrides as plain data are a **v2** item, gated on *revisiting the config-surface decision* — a user-editable config/preset file is precisely the config-DSL surface the faithful-clone identity declined for v1 (`STRATEGY.md §4.2`, `ROADMAP.md`). Until that's reopened, layout/grid configuration lives in the v1 SwiftUI settings only (`SPEC.md §5`). **Not a near-term contribution path.**

## Conventions

- **Commits:** short imperative subject; body explains *why* when non-obvious.
- **Architecture:** match the four-layer model and threading contract (`SPEC.md §6`). Event-tap callbacks must not block; AX writes go on the `swoosh.ax` serial queue.
- **Private API:** `MultitouchSupport` is loaded via `dlopen`/`dlsym`, never linked (`SPEC.md §7`).

## License

By contributing, you agree your contributions are licensed under the project's [MIT License](./LICENSE).
