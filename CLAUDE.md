# Swoosh — Claude Code project notes

Open-source macOS window snapping via trackpad gestures on titlebars. MIT, personal project, macOS 14+.

**Status: spec only.** `SPEC.md` is the canonical design. There is no code yet.

## Working in this repo

1. **Don't write code unless explicitly asked.** This is a docs repo until the user starts implementation. No `Package.swift`, no source stubs, no build scripts. The user pushed back on premature stubs once already.
2. **One spec, not many docs.** Extend `SPEC.md` rather than splitting into `ARCHITECTURE.md`, `CONTRIBUTING.md`, etc. This was a deliberate call (advisor flagged it; user agreed).
3. Refer to `SPEC.md` sections by number ("see §5.1 for threading", "see §12 for the spike"). Section numbering is stable.

## Implementation philosophy (when coding eventually starts)

- **De-risk first.** The week-1 spike (§12) must hit all three success criteria before any settings UI, onboarding, or release plumbing. If suppression breaks normal scrolling on the same machine, the project pivots.
- **The hard part is suppression, not snap math.** Layer 1 (`CGEventTap`) must swallow two-finger scroll on window titlebars only. Anywhere else the event passes through untouched. Any change that touches `EventTap` / `GestureRecognizer` must be re-validated against the §12 matrix.
- **Private-API caveat.** `MultitouchSupport.framework` is loaded at runtime via `dlsym` — never via SPM `.linkedFramework`. Plan B (NSEvent.momentumPhase, §10) stays specced even after the primary path works.
- **Project layout (§13) and threading model (§5.1) are contracts.** When code starts, match them. Event-tap callbacks must not block; AX writes go on the `swoosh.ax` serial queue.

## Out of scope (do not add)

- Apple Developer Program / signing / notarization. Deferred to v1.0 milestone (§15).
- Sparkle auto-updates, Homebrew Cask. Same.
- Telemetry. Ever.
- Older macOS fallbacks below 14.0 unless an issue is filed.
- Dock / menubar / Spaces gestures (v2; some require SIP-off scripting addition, which a large share of users won't accept).

## Repo conventions

- Default branch: `main`.
- Commits: short imperative subject, body explains why if non-obvious. Co-author trailer for AI-assisted commits.
- No global git config is set on this machine — when committing locally, pass author inline: `git -c user.name="Caio Niehues" -c user.email="cniehues1@gmail.com" commit ...`.
