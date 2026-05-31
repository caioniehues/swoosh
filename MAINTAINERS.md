# Maintainers & continuity

Swoosh depends on private/undocumented macOS surfaces (see [`CAPABILITIES.md`](./CAPABILITIES.md))
that can break on a macOS release. A free trackpad window manager dying from an unfixed
private-API break is exactly the failure mode Swoosh is built to avoid (Penc, dormant since 2021).
So continuity is a first-class concern (STRATEGY §6.1).

## Maintainer

- Caio Niehues (<cniehues1@gmail.com>) — primary maintainer.

## When a macOS beta breaks something

1. Run the regression canary: `swift test` replays the whole `fixtures/` corpus (DERISK §3–4).
   A failing fixture names the exact layer + expected-vs-actual decision.
2. To validate genuinely *new* OS behavior, record fresh fixtures on real trackpad hardware
   (capture mode — `defaults write co.swoosh.app captureMode -bool true`) and add them to `fixtures/`.
3. Any change to `EventTap` / the recognizer must re-pass the DERISK §1 matrix (the §6 hard rule).

## Continuity triggers (STRATEGY §6.1)

- **A beta break unfixed for 4 weeks** → recruit a co-maintainer / consider the NSEvent Plan B
  (DERISK §5).
- **Release-asset downloads exceed ~500/month** → evaluate notarization (→ central `homebrew/cask`)
  and a paid-convenience build, both reversible upgrades that never change the free build.
