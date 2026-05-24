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

Scaffold only. No code yet. **Start at `.sprints/epic-0-foundations/SPRINTS.md`, sprint 0.1.**

## Quickstart (local dev)

_To be filled in by Epic 0.3 once the scaffold runs locally._

## The shape, in one breath

React/TS PWA + light TS API on an Azure Static Web App → uploads land raw in Blob Storage + a `processing` record in Table Storage → blob event → Event Grid → queue → scale-to-zero Container App runs ffmpeg → finished Opus/AAC written back, record flipped to `ready` → browser caches audio for cheap replays. Login/roles via Entra. `develop`→dev, `main`→prod, separate Azure environments.
