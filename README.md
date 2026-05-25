# SLAYList — a private family music library

The **app** is private and login-gated. The **source code** is public, here, under [AGPL-3.0-or-later](LICENSE). A web app where the kids upload songs they made and play them on their devices. Not commercial, not for sale, not for public listening. See `CLAUDE.md` and `docs/ARCHITECTURE.md` for the full picture, and `CONTRIBUTING.md` if you want to submit a patch.

## If you're a developer (human or AI) starting here

1. Read **`CLAUDE.md`** (entry point + guardrails).
2. Read **`docs/ARCHITECTURE.md`** (the design) and **`docs/DECISIONS.md`** (why).
3. Look at **`.sprints/INDEX.md`** for where things stand.
4. Work proceeds sprint by sprint using the slash commands in `.claude/commands/`:
   - `/start-sprint <epic>/<sprint>` → re-establish context + plan (you approve before code).
   - `/wrap-sprint` → five-perspective skeptical review; criticals block.
   - `/close-sprint` → sync docs, prepare PR to `develop`; you merge.

## Status

Epic 0 in progress. Sprints 0.1 (repo + branches), 0.2 (monorepo scaffold + shared types), 0.3 (local run) done. See **`.sprints/INDEX.md`** for current state.

## Quickstart (local dev)

Prerequisites:
- **Node 22 LTS** (D18) — `node --version` should report `v22.x`. Use a version manager like `nvm-windows`, `fnm`, or `volta` to switch if needed.
- **pnpm 11+** (D34) — `pnpm --version` should report `11.x`. Install via `npm install -g pnpm@latest` or `corepack enable && corepack prepare pnpm@latest --activate`.
- **Azure Functions Core Tools v4** — the `func` binary on PATH. Install via the [installer](https://learn.microsoft.com/azure/azure-functions/functions-run-local) or `npm install -g azure-functions-core-tools@4`. `func --version` should report `4.x`.
- **Filesystem with symlink support** (D34) — NTFS on Windows, ext4/APFS elsewhere. `pnpm install` fails on exFAT.

Then:

```
pnpm install
pnpm dev
```

`pnpm dev` runs **four** processes concurrently via `concurrently` (with a `predev` hook that runs an initial API build first):

| Process | Port(s) | What it does |
|---|---|---|
| **storage** (Azurite) | 10000 / 10001 / 10002 | Azure Storage emulator — blob / queue / table. Required by the Azure Functions runtime even for HTTP-only apps; satisfies `func`'s `AzureWebJobsStorage` health check. Runs silently. |
| **tsc** (TypeScript watch) | — | Recompiles API source (`api/src/**`) to `api/dist/**` on save. Gives the API a save-and-reload loop comparable to Vite's HMR. |
| **api** (`func`) | 7071 | Azure Functions runtime hosting the `/api/health` endpoint (and future endpoints from Epic 4+). Reloads when the watcher updates `dist/`. |
| **web** (Vite) | 5193 | Frontend dev server with HMR. Proxies `/api/*` to `localhost:7071` so the frontend can call `/api/health` as a same-origin URL — matching deployed SWA routing. |

Browse to **`http://localhost:5193`** — you should see the "SLAYList — it works" page with a green `API: ok` round-trip indicator and an AGPL source-link footer.

Ctrl-C in the terminal stops all four. Azurite's local data lives in `.azurite/` (gitignored).

**Convenience kickoff script:** `scripts/dev.sh` (tracked, portable) checks the five dev ports for orphaned listeners from prior crashed runs, force-kills them, verifies prereq versions, then runs `pnpm dev`. Run it as `./scripts/dev.sh` from the repo root. A `dev.sh` at the repo root is gitignored if you want to drop a machine-specific override there.

Other commands:

```
pnpm test         # vitest across workspaces
pnpm typecheck    # tsc --noEmit across all workspaces (strict + noUncheckedIndexedAccess)
pnpm build        # production builds (frontend → dist/, api → dist/)
```

## The shape, in one breath

React/TS PWA + light TS API on an Azure Static Web App → uploads land raw in Blob Storage + a `processing` record in Table Storage → blob event → Event Grid → queue → scale-to-zero Container App runs ffmpeg → finished Opus/AAC written back, record flipped to `ready` → browser caches audio for cheap replays. Login/roles via Entra. `develop`→dev, `main`→prod, separate Azure environments.
