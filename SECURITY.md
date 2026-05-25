# Security policy

## Reporting a vulnerability

SLAYList is a private family-music app whose source code is public (AGPL-3.0-or-later — see `LICENSE`). If you find a security issue in the public source code, please report it privately via GitHub's **"Report a vulnerability"** button on the Security tab, or by emailing the maintainer listed on the GitHub profile. Please do not file public issues for suspected vulnerabilities.

A response acknowledging the report is the goal within a few days; this is a personal-time project, so resolution timelines are best-effort.

## A note on the open Dependabot alerts

If you're browsing this repository and notice a number of open Dependabot alerts, that's expected and triaged — not neglect. Here's the picture as of the most recent triage:

### What was fixed

The `happy-dom` advisories (including the Critical script-evaluation RCE, CVE-2025-61927) were patched by bumping `happy-dom` to `^20.0.0` (see PR #6 and the implementation note under D23 in `docs/DECISIONS.md`).

### What's left, and why it's not "open and ignored"

The remaining alerts are **dev-only transitive dependencies** of three Azure development tools:

- **`azurite`** — local Azure Storage emulator, used only by `pnpm dev` to satisfy the Azure Functions runtime's storage health check (see D35 in `docs/DECISIONS.md`).
- **`@azure/static-web-apps-cli`** — used during deploy verification only.
- **`azure-functions-core-tools`** — provides the local `func` binary used by `pnpm dev` to host the API.

All three are **devDependencies**, present only on developer machines and in CI build steps. They are **not bundled into any deployed artifact**, never run in production, never see real user data, and are not reachable from any URL the app exposes. Production data-plane separation is documented in D7 (`docs/DECISIONS.md`): dev and prod data stores are physically separate accounts; these dev tools never touch prod at all.

All three packages are also **already at their latest published npm versions** as of the most recent triage. The vulnerable transitive ranges (axios SSRF/credential-leak family; `@azure/identity` / `@azure/msal-node` ranges) are pinned by the upstream maintainers — fixes are **gated on upstream releases**, not on changes the maintainer of this repo can make today.

### How this is tracked

The residual alerts are tracked as an explicit "Emergent" entry in `docs/BACKLOG.md` with concrete re-triage triggers:

- Before Epic 1.1 (when Application Insights is wired) — re-run `pnpm audit` and check for updated dev-tool versions.
- Before Epic 2.2 (when the first deploy workflow lands) — same check, with extra attention to anything `@azure/static-web-apps-cli` pulls during deploy.
- **Escalation rule:** if a later sprint ever puts any of these packages on a *runtime* code path (rather than dev/CI-only), or if a Dependabot alert escalates to Critical on a runtime-reachable path, re-triage immediately rather than waiting for the scheduled trigger.

### Summary

The open-count number on the Security tab is what GitHub reports verbatim from npm advisories regardless of reachability. The substantive read is: the only runtime-reachable advisory found so far (happy-dom) was fixed; the remainder are dev tooling waiting on upstream and are explicitly tracked. If that picture changes, this note will too.
