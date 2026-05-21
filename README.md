# Swoosh

Open-source macOS window snapping via trackpad gestures on titlebars. A faithful, free, MIT-licensed reimagining of the snap subset of [Swish](https://highlyopinionated.co/swish/).

> **Status: spec only.** No code yet — this repo is the design document. Implementation has not started. See [SPEC.md](./SPEC.md) for the full design and roadmap.

## What it does (when finished)

Two-finger swipe on any window's titlebar snaps it to a half, quarter, or third of the screen. Normal scrolling everywhere else is untouched. Keyboard shortcuts work too.

## Why

[Swish](https://highlyopinionated.co/swish/) is great but closed-source and $16. This is a free, auditable alternative for the snap subset (no Dock/menubar/spaces gestures — see [SPEC §2](./SPEC.md#2-non-goals-v1)).

## Requirements

- macOS 14 Sonoma or newer
- Magic Trackpad (built-in or external)
- Accessibility permission (granted on first launch)

## Install (when v0.1.0 ships)

Not yet. Track the [Milestones](./SPEC.md#14-milestones).

When the first release tag exists:

```bash
# Download Swoosh.app.zip from GitHub Releases, unzip, then:
xattr -dr com.apple.quarantine /Applications/Swoosh.app
open /Applications/Swoosh.app
```

The `xattr` step is needed because v0.x builds are not code-signed (see [SPEC §15](./SPEC.md#15-project-framing) for why).

## Development status

| Milestone | State |
|---|---|
| Spec | ✓ Done — [SPEC.md](./SPEC.md) |
| Week-1 de-risk spike | Not started |
| Snap engine | Not started |
| Keyboard shortcuts | Not started |
| Settings UI | Not started |
| v0.1.0 release | Not started |

Build/run instructions will be added once there is something to build.

## Contributing

It's a personal project at this stage — issues welcome, PRs welcome but not solicited. If you want to discuss design before writing code, open a discussion.

## How it works

Three native frameworks composed:

1. **`CGEventTap`** captures two-finger scroll events system-wide.
2. **`MultitouchSupport.framework`** (private SPI) confirms exactly two fingers are down.
3. **Accessibility API** (`AXUIElement`) hit-tests the cursor against window titlebars, then writes the new frame.

See [SPEC §5](./SPEC.md#5-architecture) for the architecture diagram and threading model.

## License

[MIT](./LICENSE) © 2026 Caio Niehues
