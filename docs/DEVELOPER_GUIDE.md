# Developer Guide

For future human developers (and AI agents). Read `CLAUDE.md` and `docs/ARCHITECTURE.md` first; this is the practical "how to work on it" companion.

## Mental model in one paragraph

A React/TypeScript PWA talks to a light TypeScript API (both hosted on an Azure Static Web App). Uploads land as raw files in Blob Storage and create a song record in Table Storage marked `processing`. A blob event flows through Event Grid into a queue, which wakes a scale-to-zero Container App that runs ffmpeg, writes the finished Opus/AAC back to Blob Storage, and flips the record to `ready`. The browser caches finished audio so replays are cheap. Login and roles are Entra ID. Dev and prod are separate Azure environments driven by the `develop` and `main` branches.

## Repo layout (target)

```
/                       repo root
  CLAUDE.md             AI/human entry point — read first
  README.md             quickstart
  /docs                 ARCHITECTURE, DECISIONS, this guide, VERSIONS, BACKLOG
  /.sprints             epics/sprints + INDEX.md
  /.claude/commands     slash-command definitions (/start-sprint, /wrap-sprint, /close-sprint) — Claude Code's expected location
  /frontend             React + TS (Vite) PWA
  /api                  TypeScript API (Static Web App integrated functions)
  /transcoder           Container App: ffmpeg worker + Dockerfile
  /shared               shared TypeScript types (Song, roles, states) used by frontend + api + transcoder
  /infra                infra notes / scripts / IaC if/when added
  /.github/workflows    GitHub Actions pipelines
```

## Branches & environments

- `develop` → auto-deploys to the **dev** Azure environment.
- `main` → auto-deploys to **prod**. Human-gated merge.
- Branch protection on `main` (and ideally `develop`): no direct pushes, PR required.
- Feature work happens on short-lived branches off `develop`, named `sprint/<epic>-<sprint>-<slug>`.

## The sprint loop (practical)

1. `/start-sprint <epic>/<sprint>` — agent reloads context (CLAUDE.md → ARCHITECTURE → DECISIONS → the sprint file), audits what's already built, and proposes a plan. You approve before it breaks ground.
2. Build the user stories.
3. `/wrap-sprint` — five skeptical reviewers (sr dev, solution architect, devops, infosec, support) produce critical/moderate/low findings. **Any critical finding blocks the "proceed" recommendation.** You decide what to fix (including "fix everything now").
4. `/close-sprint` — agent updates docs/INDEX for anything the sprint changed (and flags contradictions), prepares the PR to `develop`, and on conflicts runs a Claude-Code/human consult rather than auto-resolving. You perform the merge.

## Local development

Goal: one command runs frontend + API locally; the transcoder is runnable/testable locally against a local or dev storage account.

### Prerequisites (one-time setup)

- **Node 22 LTS** (D18). Check: `node --version` → `v22.x`. Use `nvm-windows`/`fnm`/`volta` to manage versions.
- **pnpm 11+** (D34). Check: `pnpm --version` → `11.x`. Install: `corepack enable && corepack prepare pnpm@latest --activate`.
- **Azure Functions Core Tools v4** — the `func` binary on PATH. Required to run the API locally. Install: [Microsoft installer](https://learn.microsoft.com/azure/azure-functions/functions-run-local) (Windows MSI) OR `npm install -g azure-functions-core-tools@4`. Check: `func --version` → `4.x`.
- **Filesystem with symlink support** (D34 — NTFS / ext4 / APFS; exFAT breaks pnpm).

### After cloning

```
pnpm install            # installs deps for all workspaces; generates pnpm-lock.yaml on first run
pnpm dev                # three-process dev stack (storage + api + web), concurrently. Browse http://localhost:5193
pnpm run typecheck      # tsc --noEmit across all workspaces
pnpm test               # vitest across workspaces with tests
pnpm build              # production builds (frontend → frontend/dist/, api → api/dist/)
```

**Kickoff helper:** `scripts/dev.sh` is the tracked, portable, machine-agnostic kickoff script. It resolves the project root from its own location (so it works wherever you cloned the repo), checks the five dev ports for orphaned listeners, force-kills them, verifies the prereq versions, then runs `pnpm dev`. Run it as `./scripts/dev.sh` from the repo root, or with its full path from anywhere. If you want machine-specific tweaks (different ports, extra setup steps, etc.) without committing them, drop a `dev.sh` at the repo root — that exact path is gitignored.

### The dev stack (`pnpm dev`)

**Four** processes run concurrently via [`concurrently`](https://www.npmjs.com/package/concurrently) with `--kill-others-on-fail` (if one crashes, the others stop too, so failures surface immediately). A `predev` hook runs an initial `pnpm --filter @slaylist/api build` first so `func` has a `dist/` to load before the watcher takes over.

| Process | Port(s) | Purpose |
|---|---|---|
| **storage** ([Azurite](https://github.com/Azure/Azurite)) | 10000 / 10001 / 10002 | Microsoft's official Azure Storage emulator — blob / queue / table. Runs silent (`--silent --location ./.azurite`). Required by `func`'s `AzureWebJobsStorage` health check even for HTTP-only Functions; without it the func host eventually exits as "unhealthy" and takes the rest of the stack down (see D35 for the trap). Will be the local stand-in for the real Azure Storage account when Epic 4+ adds blob/table code. |
| **tsc** (TypeScript compiler in watch mode) | — | `tsc --watch --preserveWatchOutput` running in the api workspace. Recompiles `api/src/**` to `api/dist/**` on every save so the func host picks up handler edits without a manual restart. Frontend gets HMR via Vite; this gives the API a comparable iteration loop. |
| **api** (`func`) | 7071 | Azure Functions runtime hosting `/api/health` (and future endpoints). Loads compiled JS from `api/dist/`. Reads `api/local.settings.json` (auto-created from `api/local.settings.json.example` by the prestart hook on first run; `local.settings.json` is gitignored). |
| **web** (Vite) | 5193 | Frontend dev server with HMR. Proxies `/api/*` to `localhost:7071`, so the frontend code calls `/api/health` as if both halves were one origin — matching deployed SWA routing. Non-default port (5193 instead of Vite's 5173) to avoid conflicts with other local apps. |

Browse to `http://localhost:5193` once `[web]` reports `VITE ... ready`. Ctrl-C in the terminal stops all three. Azurite's local data lives in `.azurite/` (gitignored — safe to delete to reset emulator state).

### Why this dev pattern, not SWA CLI's `swa start`?

The "SWA-faithful local emulator" is the Static Web Apps CLI (`swa start`). It exists as a devDep here for Sprint 2.2's deploy-pipeline verification, but it is **not** used by `pnpm dev`. Reason: SWA CLI's local-mode does a hardcoded `require('<cwd>/azure-functions-core-tools/lib/main.js')` to start its bundled func runtime, which fails under pnpm's strict node_modules layout (discovered during Sprint 0.3 verification, even with `public-hoist-pattern` and a global `func` install).

The current `pnpm dev` pattern instead runs Azurite + tsc-watch + func + Vite directly via `concurrently`, with Vite's dev-server proxy emulating SWA's `/api/*` routing. This is reliable, matches the production routing shape from the frontend's perspective, and reserves SWA CLI for the load-bearing build verification at Sprint 2.2. If the SWA CLI bug is fixed upstream (or worked around in a way that doesn't compromise D34), `pnpm dev` can pivot back.

### Filesystem requirements (D34)

The working tree **must** live on a filesystem with symlink support — **NTFS on Windows; ext4/APFS on Linux/macOS**. **exFAT, FAT32, and certain SMB shares break `pnpm install`** with `EISDIR: illegal operation on a directory, symlink ...`. The `node-linker=hoisted` workaround exists but discards the strict-resolution benefit that justifies D34 — move the working tree to a supported filesystem rather than reaching for it.

## Secrets

Never in code, never committed. Local dev uses untracked local config; CI uses GitHub Actions secrets; runtime uses Azure app configuration. If you find a secret in the repo, treat it as compromised and rotate it.

**Azure deploy auth uses OIDC federation (D30), not a stored client secret.** GitHub Actions presents a short-lived JWT; Azure validates via federation. The federated credential is keyed to this specific repo and branch. There is no client-secret artifact to leak.

**Runtime app→storage auth follows D25's split posture:**
- SWA managed-functions API: connection string (Managed Identity unavailable on managed functions — platform-forced). Stored as SWA app setting + GitHub Actions secret.
- Container App transcoder: Managed Identity + RBAC (Storage Blob Data Contributor + Storage Table Data Contributor).

**Rotation policy:**
- The storage account connection string (D25): rotate annually or on suspicion. Procedure: regenerate the secondary key in the Azure portal → update both the SWA app setting and the GitHub Actions secret → verify next deploy → regenerate the primary key → update both again. Documented as a `infra/` runbook before Epic 9.
- The SWA deployment token (**break-glass fallback only, per D37** — NOT used by CI, NOT stored in GitHub Secrets, NOT in any SWA app setting): rotate annually or on suspicion. Procedure differs from the connection-string flow above because there's no CI propagation: SWA → Manage deployment token → **Reset** → copy the new value → update the `Deployment token (break-glass fallback)` row in `infra/dev-resources.md` Static Web App section. That's it — no app setting update, no GitHub secret update, no deploy verification needed (the token isn't on any deploy path until an operator uses it manually).
- The Application Insights connection string (D24): rotation only on suspicion (low blast radius — it grants telemetry-write only).
- OIDC federation: nothing to rotate. That's the point.

## Logging discipline (D32)

Application Insights (D24) is indexed, queryable, and hard to selectively scrub after the fact — so what enters the log must be controlled at the source.

**Hard rules:**
- Log **`ownerOid`** (opaque Entra `oid`), NEVER `ownerDisplayName` (PII per D21).
- Log **`songId`**, NEVER `title` (titles contain kids' first names, family references, event names).
- Never use a log helper that takes "an object" and serializes everything — always pass explicit fields, so a PII field can't ride in by default.
- Transcoder: never let ffmpeg's stderr flow unsanitized to App Insights. ffmpeg embeds the input filename (which is built from the title-slug per D8) in nearly every line. Mitigations (Sprint 6.1 picks one): songId-based local filenames during transcode (preferred — eliminates the leak channel) OR filename→songId substitution in captured stderr before emitting (acceptable filter).

`/wrap-sprint` InfoSec check verifies these rules every sprint that adds log statements.

## Public-repo hygiene

This repository is public from its first commit (D17), AGPL-3.0-or-later. The *app* it builds is private (login-gated, family-only) — never let one fact erode the other.

What must NOT land in any committed file:

- Secrets, tokens, connection strings, SAS URLs, Entra client secrets, storage keys.
- **Real Azure resource identifiers beyond the generic project prefix.** The pattern-derived names that fall straight out of `infra/naming-convention.md` + the public app name + the public env/region codes (e.g. `rg-music-slaylist-dev-use2`, `log-music-slaylist-dev-use2`, `appi-music-slaylist-dev-use2`) ARE acceptable in committed files — they leak nothing a reader couldn't reconstruct from the naming convention itself, they're load-bearing for the portal guides being followable, and the storage-account name (`stmusicslaylistdevuse2`) is the only globally-unique one and is still derivable. What is NOT acceptable in committed files: the **GUID-bearing identifiers** (tenant ID, subscription ID, Application Insights instrumentation key, full resource IDs of the form `/subscriptions/<guid>/...`), connection strings, deployment tokens, and SAS URLs. Those live in your gitignored `infra/dev-resources.md` + GitHub Actions secrets + Azure app settings only. The Sprint 1.1 guide's Step 8 grep check codifies the boundary: pattern-derived names are whitelisted in `infra/` and the sprint guide, but real GUIDs and connection-string fragments anywhere in `git grep` are a violation.
- **Family-identifying detail** — kid names, real ages, the family's address or location, school names, neighborhood. Code and tests refer to generic "kid 1", "uploader", "listener", etc.
- Real email addresses other than the maintainer's copyright line. Use `you@example.com` / `family@example.com` in examples.
- Real `ownerDisplayName` values (Entra `preferred_username`, typically an email/handle — PII). Use fake names like `"Alice"`, `"Test Uploader"`, or `"user@example.com"` in fixtures and tests. For `ownerOid` use any opaque placeholder (e.g., `"00000000-0000-0000-0000-000000000001"`).
- The `libraryId` field itself is safe to commit at its current value `'slaylist-home'` (generic application label, not PII, not the Entra tenant ID). If a multi-library future ever introduces real per-family identifiers, those go in config, never in code.
- **Claude Code per-user local state** — `.claude/settings.local.json` (holds local permission grants and per-machine preferences) is `.gitignore`d. `.claude/commands/` (the three project slash commands) and `.claude/settings.json` (if present — repo-shared settings) ARE committed. If you add a new tool-permission grant during work, it lands in `settings.local.json` by design; do not move it into the shared `settings.json` unless you mean every developer/agent to inherit it.

What is fine to commit publicly:

- Architecture, decisions, sprint plans, prompts (all of this).
- Generic code, generic types, generic seed data.
- The maintainer's name in copyright headers and `CONTRIBUTING.md` (Ray Klundt — by deliberate choice, see D15/D17).
- The maintainer's git author email (currently `rayklundt@outlook.com`, visible in every commit's metadata via `git log`). This is intrinsic to git and is required by the DCO sign-off (D16) — it is NOT a public-repo-hygiene violation, just a public fact of using git with DCO. Do not flag in `/wrap-sprint`.
- **Personal-machine local paths.** Never commit a path that identifies your specific machine, user, or project directory — `C:\Users\<you>\code\slaylist`, `D:\projects\slaylist`, `/home/<you>/code/slaylist`, `~/dev/slaylist`, etc. Document the project's *constraints* (filesystem must support symlinks per D34, OS-specific tooling) but use generic placeholders (`<your-project-path>`, "your project directory") for the path itself. **Commit messages count** — `git log` is permanent on a public repo. `/wrap-sprint` InfoSec checks for this every sprint.

If you find a violation, treat the affected value as compromised (rotate the secret, rename the resource, etc.) and remove it in a follow-up commit. `git history` is forever on a public repo — prevention beats cleanup.

## Node version

Node **22 LTS** is pinned across the whole repo (frontend, API, transcoder). The API runtime is the binding constraint — Static Web Apps' managed-functions API supports `node:22` as GA (verified 2026-05-24, see `docs/VERSIONS.md`). Frontend and transcoder follow the API for consistency. Do not split versions across packages.

## Testing (D23)

Framework: **Vitest**, pinned from Sprint 0.2. Tests are co-located (`*.test.ts` next to the source) unless a package explicitly diverges. `npm test` at the root runs across all workspaces.

CI gate is **soft** during Epics 0–3 (scaffolding) — tests run on every push and the result shows red/green in the Actions log and PR check, but a failure does **not** block merge. From **Sprint 4.1 onward** the gate is **hard** — failing tests block merge to `develop`. The flip is an explicit Sprint 4.1 acceptance criterion, not relying on memory; the soft-mode breadcrumb is a comment in the Epic 2 workflow file that Sprint 4.1 removes.

## CI

**GitHub Actions** is the CI provider. Workflows live in `.github/workflows/`. The first workflow lands in Epic 2 (build + deploy + soft-mode tests + auth-gate verification). The transcoder image pipeline is a separate workflow added in Sprint 6.0. Prod-deploy extension lands in Sprint 9.2.

## Observability (D24)

**Application Insights** is the single failure-observability sink, one instance per environment (dev created in Sprint 1.1, prod in Sprint 9.1). SWA managed functions, the Container App transcoder, and Storage diagnostics all feed into it. When something fails — a transcode, a queue dead-letter, a deploy, an API 500 — App Insights is where you look. Save useful KQL queries in `infra/` notes so they're not re-derived under pressure.

The budget alert (Sprint 1.1 / 9.1) is **cost** observability — a separate concern from failure observability. Don't conflate.

## Storage auth (D25)

The SWA managed-functions API authenticates to Storage via a **connection string** (Managed Identity is unavailable on managed functions — platform-forced). The connection string lives in SWA app settings + GitHub Actions secrets, never in code. The Container App transcoder uses **Managed Identity** + RBAC role assignments. Split auth posture is intentional and recorded in D25; don't try to unify it without first moving to bring-your-own-functions.

## When you want to change an architectural decision

1. Find it in `docs/DECISIONS.md`.
2. If it's there, the alternative was likely already considered — read why it was rejected.
3. If you still think it should change, raise it with the human with the tradeoff. Do not change it silently.
4. If approved, update DECISIONS.md (new entry superseding the old) and ARCHITECTURE.md in the same PR.

## Cost discipline

This should cost near-nothing at rest. Keep the Container App scale-to-zero, keep audio browser-cacheable, keep dev resources minimal. The Epic 1 budget alert is the safety net — don't disable it.
