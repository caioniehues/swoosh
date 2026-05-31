# Swoosh — capability manifest

> The complete, audited list of every **private / undocumented** OS surface Swoosh touches, the
> entitlements it needs, and the permissions it requests. This is the trust contract (STRATEGY
> §5): Swoosh is a *free, auditable* alternative to a closed binary, so every non-public surface
> is declared here, and CI (`scripts/check-capabilities.sh`, run by `.github/workflows/ci.yml`)
> fails if the code uses any private symbol or attribute not listed below.
>
> Public APIs (`CGEventTap`, `AXUIElement` public attributes, `CGWindowList`, `NSScreen`,
> `UserDefaults`) are not listed — they need no special trust.

## Private frameworks (loaded at runtime via `dlopen`/`dlsym`, never linked)

All private-framework loading is confined to `Sources/SwooshKit/MultitouchClient.swift`
(enforced by the `dlopen-only-in-multitouchclient` ast-grep rule). Framework:
`/System/Library/PrivateFrameworks/MultitouchSupport.framework`.

### Finger-count (Layer 2 — the two-finger discriminant)

| Symbol | Use |
|---|---|
| `MTDeviceCreateList` | enumerate built-in + external trackpads |
| `MTDeviceIsBuiltIn` | classify a device |
| `MTDeviceGetDeviceID` | device id (for the actuator); offset-64 hack not needed on macOS 26 |
| `MTRegisterContactFrameCallbackWithRefcon` | receive contact frames (the live finger count) |
| `MTDeviceStart` | start the contact stream |
| `MTDeviceStop` | stop the contact stream |

### Haptics (Layer 4 — ready/done taps, SPEC §4.4)

| Symbol | Use |
|---|---|
| `MTActuatorCreateFromDeviceID` | create an actuator for the trackpad |
| `MTActuatorOpen` | open the actuator |
| `MTActuatorActuate` | fire a haptic tap (actuation ids 1–6) |
| `MTActuatorClose` | close the actuator |

## Private / undocumented Accessibility attributes

Used only inside `Sources/SwooshKit/SnapApplier.swift` (Layer 4; AX writes are confined there by
the `ax-write-only-in-layer4` ast-grep rule).

| Attribute | Use |
|---|---|
| `AXFullScreen` | exit native fullscreen by setting it `false` (SPEC §4.6); no public equivalent |
| `AXEnhancedUserInterface` | temporarily cleared before AX position writes to stop Chrome/Electron corrupting the move (SPEC §10 / KTD7) |

## Entitlements

| Entitlement | Why |
|---|---|
| `com.apple.security.cs.disable-library-validation` | required to `dlopen` the unsigned-by-us private framework |
| (no app sandbox) | the sandbox forbids both AX writes and `MultitouchSupport` access |

## TCC permissions requested

| Permission | Status |
|---|---|
| Accessibility | **required** — the event tap + AX window writes |
| Input Monitoring | **uncertain** — the live MultitouchSupport contact *stream* may need it on macOS 26; enumeration does not. Untested (KTD6, `spike/m0/RESULTS.md`). Requested only if proven necessary. |

## Not used (explicitly)

- No network. No telemetry. No analytics. Ever (STRATEGY, CLAUDE.md) — enforced by the
  `no-network-in-sources` ast-grep rule.
- No `_AXUIElementGetWindow` or other private AX SPI beyond the two attributes above.
