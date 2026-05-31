# Swoosh

Open-source macOS window snapping and resizing via two-finger **trackpad gestures on titlebars** — a free, auditable, MIT-licensed alternative to [Swish](https://highlyopinionated.co/swish/).

> **Status: spec only.** No code yet — this repo is the design. See [`STRATEGY.md`](./STRATEGY.md) (why), [`SPEC.md`](./SPEC.md) (how), [`ROADMAP.md`](./ROADMAP.md) (when).

## What it does (when finished)

- **Two-finger swipe on any window's titlebar** snaps it to a half, quarter, third — or any fraction of the screen. Normal scrolling everywhere else is untouched.
- **Drag the gap between two snapped windows** to resize both at once.
- **Haptic feedback** marks the moment a gesture commits, so snapping feels native.
- **Keyboard shortcuts** for every action.
- **Beats Swish's 3×3 ceiling** — the engine is fraction-native, so ultrawide 4- and 5-column layouts work on day one.

## Why

[Swish](https://highlyopinionated.co/swish/) is excellent but **closed-source and $16**. Swoosh is the free, auditable alternative for people who can't or won't pay, who won't grant Accessibility to a closed binary, or who want to fork and extend. It matches Swish's *feel* (titlebar swipe + divider-drag + haptics) and beats its single most-requested missing feature — custom window sizes. See [`STRATEGY.md`](./STRATEGY.md) for the full positioning, including why this still matters once macOS tiles windows for free.

## Trust

- **No telemetry. Ever.** No analytics, no network calls in the gesture path.
- **Free to users, forever** (MIT). The only permission requested is **Accessibility** — needed to hit-test titlebars and move windows; nothing else, and nothing leaves your machine.
- Auditability is the point: the code is open precisely because an Accessibility-granted utility should be inspectable. Swoosh uses a few **private Apple APIs** (finger-count, and likely haptics) — every one is enumerated in a **CI-asserted capability manifest that ships at v1**, so a change that widens the app's reach fails CI. A live "what did it touch" inspector is planned ([`ROADMAP.md`](./ROADMAP.md)).

## Requirements

- macOS 26 (Tahoe) — Swoosh targets the latest macOS only
- Magic Trackpad (built-in or external)
- Accessibility permission (granted on first launch)

## Install (when v0.1.0 ships)

Not yet. Track the [milestones](./ROADMAP.md#milestones).

When the first release tag exists, install via the Swoosh Homebrew tap (no `$99` Apple signing, no scary `xattr` dance — the tap handles quarantine for you):

```bash
brew install --cask caioniehues/tap/swoosh
```

This uses a self-owned tap with a quarantine-stripping postflight (the same approach AeroSpace uses). A notarized build in the central `homebrew/cask` is a later, traction-dependent upgrade — see [`ROADMAP.md`](./ROADMAP.md#distribution--the-cask-cutoff-precisely).

> Prefer not to have the quarantine flag stripped for you? You'll also be able to **build from source** (`swift build`) and run your own binary — the trust-maximal path for the security-conscious.

## Development status

| Milestone | State |
|---|---|
| Strategy + spec | ✓ Done — [`STRATEGY.md`](./STRATEGY.md), [`SPEC.md`](./SPEC.md) |
| M0 — de-risk spike | ✓ Done — GO on macOS 26 ([`DERISK.md`](./DERISK.md)) |
| M1 — snap engine + fixture harness | Not started |
| M2 — recognizer + suppression | Not started |
| M3 — divider-drag + haptics | Not started |
| v0.1.0 release | Not started |

Build/run instructions arrive once there's something to build.

## Contributing

It's an early product-stage project — issues and PRs welcome. The lowest-bar first contribution is **submitting a gesture fixture for a bug you hit** (no Swift required). See [`CONTRIBUTING.md`](./CONTRIBUTING.md).

## How it works

Native frameworks composed (see [`SPEC.md §6`](./SPEC.md#6-architecture)):

1. **`CGEventTap`** captures two-finger scroll events system-wide and suppresses them *only* over titlebars — the suppress/pass decision is made synchronously from fast window geometry (`CGWindowList`), never a slow lookup.
2. **`MultitouchSupport.framework`** (private SPI) confirms exactly two fingers are down — and likely actuates the haptic taps.
3. **Accessibility API** (`AXUIElement`) locates the precise window and writes its new frame.

The private surfaces (2, plus the undocumented attribute used to exit fullscreen) are all listed in the capability manifest — see [Trust](#trust).

## License

[MIT](./LICENSE) © 2026 Caio Niehues
