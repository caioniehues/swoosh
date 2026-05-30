# M0 de-risk spike (throwaway)

A single `swiftc`-built bare binary that proves Swoosh's four load-bearing
mechanisms (S1–S4) before any product code is written. **This directory is
deleted once the M0 gate resolves** — only the durable `RESULTS.md` (U6)
survives. It is *not* the product skeleton (no `Package.swift`, no app bundle).

Plan: [`docs/plans/2026-05-30-001-feat-m0-derisk-spike-plan.md`](../../docs/plans/2026-05-30-001-feat-m0-derisk-spike-plan.md).

## Build

```sh
sh spike/m0/build.sh      # → build/m0spike (gitignored), ad-hoc signed
```

Requires the Xcode/CLT Swift toolchain. Apple Silicon only is assumed for the
primary path (the private framework is loaded via `dlopen`/`dlsym` because
arm64e pointer authentication bus-errors on direct linkage).

## Run

```sh
build/m0spike scaffold    # U1 smoke: load/struct/atomic/TCC, writes JSONL
```

Set `M0_LOG=/path/to/log.jsonl` to control the decision-log path
(default: `$TMPDIR/swoosh-m0.jsonl`).

## Permissions (interactive — required for U2–U5)

The later probes need TCC grants that only a human can approve in
**System Settings → Privacy & Security**:

| Probe | Permission | Why |
|---|---|---|
| U3 (S1, active CGEventTap) + U4 (S3, AX writes) | **Accessibility** | active event tap + window move/resize |
| U2 (S2, MultitouchSupport) | **Input Monitoring** | contact-frame callbacks (this is the KTD6 measurement) |

> Re-signing churn: each ad-hoc rebuild can invalidate a prior grant. If a probe
> reports `accessibility: false` / `inputMonitoring: denied` after a rebuild,
> remove and re-add `build/m0spike` in System Settings (or use a stable signing
> identity). Every probe logs its own trust state at startup so a stale grant is
> never misread as a mechanism failure.

## The gate

The go/no-go resolves only when S1–S4 are green on **macOS 14, 15, and 26**
with an external Magic Trackpad on each. A single machine covers one OS cell;
record partial results and name the unproven OSes (U6 / `RESULTS.md`).
