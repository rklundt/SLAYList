# Versions

Tracks notable versions/milestones of the project and key dependency/tooling versions. Updated by `/close-sprint` when a sprint changes something version-worthy.

## Project milestones

| Version | Date | Milestone |
|---|---|---|
| 0.0.1 | (scaffold) | Initial project scaffold: docs, sprint structure, command definitions. No code yet. |
| 0.0.2 | 2026-05-24 | Pre-Epic-0 alignment: AGPL-3.0-or-later licensing (D15), DCO + relicensing grant (D16), public repo from commit one (D17), Node 22 LTS + npm workspaces pinned (D18). |
| 0.0.3 | 2026-05-24 | Sprint 0.1 complete: public GitHub repo at `rklundt/SLAYList`; `develop` + `main` with branch protection; D31 baseline 3/4 (secret scanning, push protection, Dependabot security updates) — CodeQL deferred to Sprint 0.2 retry because GitHub's default-setup requires detected source languages and the initial scaffold is markdown-only. |
| 0.0.4 | 2026-05-24 | Sprint 0.2 complete: monorepo scaffold (pnpm 11.3.0 workspaces per D34, supersedes D18's npm pin; working tree moved off exFAT to an NTFS path due to pnpm's symlink requirement — see D34 implementation note); `/shared` types module per D19/D21 with locked `SongState`/`Role`/`DEFAULT_LIBRARY_ID`; Vitest 3.2.4 + TypeScript 5.9.3 + `@types/node` 22.19.19 with strict + noUncheckedIndexedAccess (D29) clean across all 4 workspaces; 5 invariant tests passing. CodeQL retry (D31) still pending — actually fires post-merge of this sprint's PR, when TS code lands on default branch. New public-repo hygiene rule: no personal-machine local paths in committed files or commit messages. |
| 0.0.5 | 2026-05-24 | Sprint 0.2 post-merge: CodeQL default-setup configured against the now-TypeScript-containing develop branch (D31 baseline 4/4 complete). Correct HTTP verb confirmed as `PATCH`, not `PUT` — both Sprint 0.1 and Sprint 0.2 retry attempts had used PUT and 404'd for compounded reasons (Sprint 0.1: no language to detect; Sprint 0.2: wrong verb). Documented in D31's resolution note + Sprint 0.2 SPRINTS.md acceptance line. |

## Key tooling / dependency versions

| Item | Version | Notes |
|---|---|---|
| Node.js | **22 LTS** | Pinned across frontend, API, transcoder. Set by API constraint (D18). |
| Package manager | **pnpm 11.3.0** (D34, supersedes D18's npm pin) | Pinned via `package.json` `packageManager` field (corepack-compatible). CI uses `pnpm install --frozen-lockfile`. Working tree MUST be on a filesystem with symlink support (NTFS on Windows, ext4/APFS on Linux/macOS — exFAT/FAT32 break pnpm; see D34 implementation note). |
| Monorepo strategy | **pnpm workspaces** (D34) | `pnpm-workspace.yaml` lists `shared`, `api`, `frontend`, `transcoder`. Internal deps use the `workspace:*` protocol. pnpm 11 settings (e.g., `allowBuilds`) live in `pnpm-workspace.yaml`, not in `package.json`. |
| Frontend framework | React + Vite (TS) | Versions pinned in Epic 0.2 when the scaffold lands. |
| API runtime | Azure Static Web Apps managed functions (Azure Functions v4, Node 22) | Set `apiRuntime: "node:22"` in `staticwebapp.config.json`. |
| Transcoder | ffmpeg in a Docker image | Base image + ffmpeg version pinned in Epic 6. |
| Testing framework | **Vitest 3.2.4** (D23) | Pinned from Sprint 0.2 (range `^3.0.0` in `package.json`; exact patch in `pnpm-lock.yaml`). CI gate is **soft** during Epics 0–3 (advisory, runs but does not block merge) and **hard** from Sprint 4.1 onward (failing tests block merge to `develop`). The flip is an explicit Sprint 4.1 acceptance criterion — not memory-dependent. |
| TypeScript | **5.9.3** with `strict: true` + `noUncheckedIndexedAccess: true` (D29) | Pinned from Sprint 0.2 (range `^5.7.0` in `package.json`; exact patch in `pnpm-lock.yaml`). Root `tsconfig.json` carries the strict settings; all workspaces extend the root. No workspace silently overrides these flags downward. |
| `@types/node` | **22.19.19** | Pinned to the 22.x line to match Node 22 runtime (D18). Range `^22.10.0` in `package.json`; exact patch in `pnpm-lock.yaml`. |
| Azure deploy auth | **OIDC federation** (D30) | Federated Entra app registration; no long-lived client secret stored in GitHub Secrets. Federated credentials keyed to repo + branch. Set up at Sprint 2.1. |
| GitHub repo security | **Secret scanning + push protection + Dependabot security updates + CodeQL** (D31) | All enabled at Sprint 0.1. Free on public repos. Push protection is the critical control. |
| CI provider | **GitHub Actions** | Workflows live in `.github/workflows/`. Chosen by Epic 2's pipeline. No other CI provider in scope. |
| Observability sink | **Application Insights** (D24) | Single failure-observability sink per environment. Created in Sprint 1.1 (dev) and Sprint 9.1 (prod). Fed by SWA managed functions, the Container App transcoder, and Storage diagnostics. Cost-observability (budget alert) is a separate concern with its own Epic 1.1 / 9.1 acceptance. |
| SWA tier (dev) | **Free** (D26) | Sufficient for the architecture as designed; Standard is not needed yet. |
| SWA tier (prod) | **Decided in Sprint 9.1** (D26) | Free or Standard; Standard only if custom domain is wanted. Documented known future fork. |
| Budget alert | **$15/month (dev)** | Generous enough not to false-alarm; low enough that anything runaway trips it. Prod alert level decided in Sprint 9.1. |
| Azure resource API/SKU choices | TBD | Filled in Epic 1. |

## Verified runtime support — Static Web Apps managed functions

Node 22 GA support for SWA managed functions verified **2026-05-24** against:

- Primary (authoritative): <https://learn.microsoft.com/en-us/azure/static-web-apps/languages-runtimes> — page last updated 2026-02-25. The Node 22 row in the API runtime table reads: *Node.js 22.x | Linux | Azure Functions 4.x | `apiRuntime` value `node:22` | no end-of-support date*. **This is the SWA-integrated-Functions-specific check** — the `apiRuntime` column header is exactly the field you set in `staticwebapp.config.json` → `platform.apiRuntime`, so `"node:22"` is the verbatim valid value, not an inference from "Node 22 is LTS." This addresses the long-standing concern that SWA's integrated Functions runtime can lag the latest LTS — for Node 22, it does not.
- Cross-check: <https://learn.microsoft.com/en-us/azure/azure-functions/functions-versions> — page last updated 2026-04-17. Lists Node 22 as GA on Functions v4, expected EoS 2027-04-30.
- Stale page caveat: <https://learn.microsoft.com/en-us/azure/static-web-apps/apis-functions> — the "Constraints" table on this page still lists Node 12/14/16/18/20-preview and is internally inconsistent with the languages-runtimes page. The languages-runtimes page is authoritative.

Re-verify these links when bumping Node major or before Epic 2 if more than a quarter has passed.

## How to update

`/close-sprint` proposes additions here when a sprint pins a version, adds a dependency, or hits a project milestone. Keep it terse — this is a ledger, not a changelog narrative (narrative lives in PR descriptions).
