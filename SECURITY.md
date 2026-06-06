# Security policy

## Reporting a vulnerability

SLAYList is a private family-music app whose source code is public (AGPL-3.0-or-later — see `LICENSE`). If you find a security issue in the public source code, please report it privately via GitHub's **"Report a vulnerability"** button on the Security tab, or by emailing the maintainer listed on the GitHub profile. Please do not file public issues for suspected vulnerabilities.

A response acknowledging the report is the goal within a few days; this is a personal-time project, so resolution timelines are best-effort.

## A note on the open Dependabot alerts

If you're browsing this repository and notice Dependabot alerts, they're triaged — not neglect. Every alert to date has been a **dev-only transitive dependency** (`scope=development`) of Azure development tooling, never a runtime/deployed dependency. Here's the picture as of the **Sprint 3.1.5 security triage**:

### What was fixed

- The `happy-dom` advisories (including the Critical script-evaluation RCE, CVE-2025-61927) were patched by bumping `happy-dom` to `^20.0.0` (PR #6; implementation note under D23 in `docs/DECISIONS.md`).
- **Sprint 3.1.5 triage:** the bulk of the dev-tool transitive advisories — the entire `axios` SSRF / credential-leak / prototype-pollution family, plus `tmp`, `@azure/identity`, `tough-cookie`, and `xml2js` — were patched by forcing fixed versions via **`overrides` in `pnpm-workspace.yaml`**. Because these are dev-only, the overrides were applied **empirically and verified not to break the tooling**: a clean build, the full test suite, the `swa`/`func` CLIs loading, and azurite blob/queue/table round-trips all pass against the bumped versions. The overrides touch only the dev tree — the deployed API is built from an isolated `--ignore-workspace` install that doesn't see them, and the frontend uses `fetch`, not axios.

### What's left, and why it's not "open and ignored"

After the 3.1.5 overrides, the only remaining alert is **`uuid`** (2 instances, medium — GHSA-w5hq-g745-h8pq, a missing buffer-bounds check when a `buf` argument is passed). It **cannot be patched**: the fix lands in `uuid` >= 11.1.1, which removed the `uuid/v4` subpath export that azurite's legacy `@azure/ms-rest-js@1.11.2` does `require('uuid/v4')` against — forcing the patched `uuid` crashes azurite at load (`ERR_PACKAGE_PATH_NOT_EXPORTED`, verified). So `uuid` stays at the version azurite needs.

This is acceptable because the advisory is:

- **dev-only** — `uuid` here is a transitive of **`azurite`** (the local Azure Storage emulator, D35), a devDependency never bundled into any deployed artifact, never run in production, never near real user data (D7 keeps dev and prod data stores physically separate).
- **unreachable in our use** — triggering it requires calling `uuid` with an attacker-controlled `buf`; ms-rest-js never passes one, and our usage exposes no such path.

These 2 alerts are **dismissed in GitHub with reason "Vulnerable code is not actually used"**, not left silently open.

### How this is tracked

Tracked as an "Emergent" entry in `docs/BACKLOG.md`:

- **The overrides carry a maintenance cost** — they pin transitive deps, so a stale override can hold a dep *back*. When `azurite` / `@azure/static-web-apps-cli` update their own dependency ranges, re-check the overrides and **re-verify the dev stack** (azurite round-trip + build + tests).
- **`uuid` re-check trigger:** if azurite ever drops `@azure/ms-rest-js@1.x` (or it stops using the `uuid/v4` subpath), force the patched `uuid` and remove the dismissal.
- **Escalation rule:** if any of these packages ever lands on a *runtime* code path (not dev/CI-only), re-triage immediately rather than waiting.

### Summary

The Security-tab count is what GitHub reports verbatim from npm advisories regardless of reachability. The substantive read: every advisory has been dev-only; the runtime-reachable one ever found (happy-dom) was fixed; Sprint 3.1.5 patched the rest of the dev-tool family that *could* be patched without breaking the emulator; the lone holdout (`uuid`) is dev-only, unreachable, and dismissed with reason. If that picture changes, this note will too.
