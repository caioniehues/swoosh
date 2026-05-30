# Swoosh — Strategy

> The product's decision-of-record: what Swoosh is, who it's for, and the four strategic decisions that govern everything in `SPEC.md`, `DERISK.md`, and `ROADMAP.md`.
> Last updated: 2026-05-30.

Swoosh is a **free, open-source, MIT-licensed macOS app that snaps and resizes windows via two-finger trackpad gestures on window titlebars** — the open, auditable alternative to [Swish](https://highlyopinionated.co/swish/) ($16, closed-source). macOS 14+.

---

## 1. The thesis — an empty cell in the market

Map the macOS window-manager market on two axes — *input model* × *license* — and exactly one cell is empty:

|                    | Keyboard / tiling                                  | Trackpad gesture                |
|--------------------|----------------------------------------------------|---------------------------------|
| **Free / OSS**     | Rectangle (~29k★), AeroSpace (~21k★), Loop (~10.8k★) | **← empty →**                   |
| **Paid / closed**  | Magnet, Moom, BetterSnapTool                        | Swish ($16), BetterTouchTool, Multitouch |

The *free + open-source + trackpad-gesture* cell has had exactly one occupant — **Penc** — and it has been abandoned since July 2021. This is the Rectangle-vs-Magnet opening, ~7 years later, in the gesture niche.

**Why the cell stayed empty:** the product leans on private and undocumented APIs that break on macOS releases — `MultitouchSupport.framework` (finger-count SPI), likely `MTActuator` (haptics), and the private `"AXFullScreen"` attribute — composed with the public `CGEventTap` and `AXUIElement`. That fragility is real — it's what made Penc go dormant — and it is why our de-risk discipline (`DERISK.md`) and the fixture harness are first-class, not afterthoughts. (Full private-surface accounting: §5.)

**Demand, honestly.** The empty cell is read above as a *supply-side* gap (the integration is hard), but the same data — Penc at ~1.2k★ vs Rectangle at ~29k★ — also admits a *demand-side* reading: the free trackpad-gesture audience may simply be smaller than the free keyboard/tiling one. The Rectangle-vs-Magnet analogy assumes a Rectangle-scale latent demand the gesture cell has *not* proven. We treat demand as **real but unsized**: the signals worth weighting are the volume of "free Swish" / "Swish alternative" threads, Swish's own user base, the BTT/Multitouch gesture cohort, and ultrawide-user complaints. If that evidence stays thin, size the bet toward Penc-to-mid scale, not Rectangle scale — the niche can still justify the project (§7), but the opening is not a proven Rectangle-sized market.

## 2. The existential question — why Swoosh once macOS tiles for free?

The real competitor is **not Swish — it's Apple.** macOS 15+ ships free, built-in drag-to-edge tiling. Once the OS matches "free," only three differentiators survive, and the plan is built on them:

1. **Gesture feel.** Titlebar two-finger swipe, **divider-drag multi-window resize**, and **haptic threshold feedback** — none of which native tiling does. This is what Swish users *love*, and it is the product's soul.
2. **Auditability you can experience.** Not just "it's open source" (table stakes — every competitor in this niche is already MIT) but a **CI-asserted capability manifest** — a machine-readable list of every private API and entitlement the app touches, enforced so a PR that widens that reach fails CI. This **ships at v1** as a repo/CI artifact (cheap, independent of the app); the live "what did it touch" inspector is the post-v1 deepening (§5, `ROADMAP.md`). The differentiator closed Swish and Apple's tiling structurally cannot copy.
3. **Beyond the 3×3 cap.** A fraction/pixel-native engine ships ultrawide 4–5 column layouts and arbitrary window sizes on day one — Swish's single most-requested unmet feature, which it defers to an unshipped "Swish 2."

## 3. Who it's for

- **Primary:** Swish-curious and current-Swish users who want the same feel without the $16 or the closed-source trust ask — especially ultrawide-monitor users hitting the 3×3 ceiling.
- **Secondary:** Security-conscious users who won't grant Accessibility to a closed binary (the Karabiner/Rectangle trust audience).
- **Tertiary:** BetterTouchTool/Multitouch owners frustrated by the trackpad-freeze conflict — the highest-intent switcher pool.

## 4. Strategic decisions (resolved)

These four forks were decided during the 2026-05-30 re-plan (grounding: `docs/ideation/2026-05-30-swoosh-fresh-planning.md`). They are **settled** — a future session should not relitigate them without new information.

### 4.1 Charter — **Product (grow it).**
Swoosh deliberately occupies the empty cell; adoption is a goal, not an accident. This unlocks the Rectangle playbook: capture the "Swish is great but not free" threads, an HN/Reddit launch, Homebrew distribution, a preset gallery, and BTT-migration positioning. It also obligates a sustainability answer (§6) and a real maintenance commitment against every macOS beta (`DERISK.md`).

### 4.2 Identity — **Faithful clone (not a platform).**
A tight, opinionated snap tool that matches Swish's feel and beats its 3×3 cap — *not* a programmable "Hammerspoon for the trackpad." The snap engine is built fraction/pixel-native (`SPEC.md §5`), which already delivers the headline win, so we do not need a config-DSL or control socket to differentiate. The fraction-native engine keeps a cheap seam if we ever reconsider, but a scripting platform is an explicit **non-goal**.

### 4.3 Durability — **MultitouchSupport load-bearing; NSEvent is Plan B.**
The private finger-count SPI is the primary path because, for *system-wide* titlebar gestures over arbitrary apps' windows, the public `NSEvent` touch API is too constrained to be primary (this is precisely why Swish and Penc used the SPI). We accept the fragility and neutralize it with the **record-and-replay fixture harness** (`DERISK.md`): every macOS beta becomes "replay the corpus, diff the decisions" instead of an emergency. The NSEvent path stays specced as a documented fallback, and its trigger conditions live in `DERISK.md`.

### 4.4 Distribution — **Self-owned Homebrew tap now; notarize later.**
Ship today via our own tap with an `xattr` postflight (the AeroSpace model): one-line `brew install`, **$0 cost**, no Apple gatekeeping. The Sept 1 2026 homebrew/cask cutoff for unnotarized casks means the *central* cask channel requires notarization — so notarization (Apple Developer Program, $99/yr + a CI notarize/staple pipeline) is a **deferred, reversible upgrade** we buy once traction justifies it, not a launch blocker.

**Closing the circularity:** a self-owned tap has near-zero organic discovery (a user must already know the tap string), and the central cask we defer is *the* high-discovery channel — so traction cannot come from distribution alone. The **bootstrap-discovery engine** is therefore explicit and notarization-independent: a "Show HN" / r/macapps launch, capturing the "free Swish" / "Swish alternative" search threads, and GitHub topic + `awesome-mac` / `awesome-macos` list placement. **Trigger to notarize:** when GitHub release-asset downloads exceed ~500/month (a telemetry-free install proxy, §7), the central-cask channel is worth $99/yr. See `ROADMAP.md`.

## 5. Trust posture

- **No telemetry. Ever.** No analytics, no network calls in the hot path, no "anonymous usage data."
- **Auditability is a load-bearing promise, not a marketing line.** Open source for an Accessibility-hungry tool is a contract; we will not gate settings behind sponsorship (the mistake that drew backlash for Loop).
- **Make trust experienceable:** the **CI-asserted capability manifest ships at v1** — a machine-readable list of the private/undocumented surfaces and entitlements the app touches, enforced so a PR that widens that reach fails CI until it updates the manifest. The optional live inspector of AX reads/writes and event-tap suppress/pass decisions is the **post-v1** deepening.
- **The private-surface ledger** (what the manifest enumerates): `MultitouchSupport.framework` finger-count SPI (load-bearing); `MTActuator` haptic actuation (if the spike shows the public path can't actuate from the background — `SPEC.md §4.4`); the undocumented `"AXFullScreen"` attribute for exit-fullscreen (`SPEC.md §4.6`); plus the public `CGEventTap` and `AXUIElement`. Up to **four** private surfaces — more reason, not less, to make them auditable.
- **Least privilege:** request Accessibility only; do not request Input Monitoring unless a macOS change forces the MultitouchSupport path to need it (tracked as a risk in `SPEC.md`).

## 6. Pricing & sustainability

- **Free to users, forever.** MIT.
- **Why MIT (not copyleft):** auditability is our moat, and MIT permits anyone — even Swish's vendor — to fork, re-close, and ship a paid build, which copyleft (GPL/MPL) would prevent. We choose MIT anyway: the niche norm is permissive (Rectangle, AeroSpace, Loop are all MIT), contribution friction is lower, and the moat is the *live* trust posture and community, not source exclusivity — a re-closed fork forfeits exactly the auditability that is the point. If re-closure ever becomes a real concern, MPL (file-level copyleft, low friction) is the fallback. A deliberate choice, not a default.
- **Funding ladder (only as needed):** optional GitHub Sponsors / Ko-fi; *if and when* maintenance burden demands it, an optional **paid convenience build** (notarized, auto-updating) sold alongside the always-free source build — the proven Rectangle Pro / many-OSS-utility model. No core feature is ever paywalled; no settings are ever sponsor-gated.
- **The $99/yr Apple fee is a developer cost, not a user cost.** Deferred until growth justifies the central-cask channel (§4.4).

### 6.1 Maintainer continuity (the real anti-Penc)

Penc did not die from *undetected* breakage — it died because its solo maintainer stopped shipping fixes. Detection (the fixture canary, `DERISK.md §4`) is necessary but not sufficient; the failure mode is **fix-throughput**, not blindness. So:

- **Bus-factor is named, not wished away.** This is a solo project today; that is the single biggest risk to the survival thesis.
- **Continuity triggers.** If a canary-detected beta-break stays unfixed for **4 weeks**, or release downloads pass the notarization trigger (§4.4): actively recruit a co-maintainer and/or stand up the paid convenience build to fund maintenance time.
- **Hand-off readiness.** The de-risk docs, fixture corpus, and capability manifest exist partly so a second maintainer can pick up the private-API surface without re-deriving it. A `MAINTAINERS` / hand-off note is added at v0.1.0.
- The §7 durability metric is **time-to-fix**, not just time-to-detect.

## 7. Success metrics (product charter)

Every metric here is collectable under the no-telemetry + self-tap constraints — none requires phoning home or central-cask analytics we don't have yet.

- **Adoption:** GitHub stars (read: ~1k in the first 6 months as a rough go/no-go), GitHub **release-asset download count** (the install proxy — noisy, counts upgrades/CI pulls, but real and telemetry-free), and tap-repo clone/traffic stats. *Not* "Homebrew tap install count" — third-party taps publish no install analytics; that number exists only once on the central cask.
- **Migration:** mentions in "Swish alternative" / "free Swish" searches and threads; BTT/Swish switchers self-identifying in issues.
- **Trust proof:** the capability manifest exists and CI enforces it **at v1**; zero telemetry verifiable from source.
- **Durability proof (anti-Penc):** the fixture corpus catches a real macOS-beta regression *before* a user reports it **and** it is fixed-and-released within a target **time-to-fix** — detection without repair is exactly Penc's grave (§6.1).

## 8. Strategic non-goals

- A scripting platform / control socket / arbitrary action binding (the platform identity we declined).
- Dock, menubar, App-Switcher, and Spaces gestures in v1 (some require SIP-off scripting additions a large share of users won't accept) — deferred, see `SPEC.md §2`.
- Mac App Store distribution (the sandbox forbids both AX writes and `MultitouchSupport` access — structurally impossible).
- Charging users for core functionality; gating settings behind sponsorship.
