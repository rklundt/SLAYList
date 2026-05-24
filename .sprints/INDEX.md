# Sprint INDEX

High-level map of all epics and sprints, with status. **Kept current by `/close-sprint`.** Use this to reason about downstream impact: before changing something, check which later sprints depend on it.

Status legend: ⬜ not started · 🟡 in progress · ✅ done · ⏸ blocked

## Dependency shape (read top to bottom)

```
Epic 0 Foundations ──► Epic 1 Azure dev resources ──► Epic 2 Pipeline (on skeleton)
                                                              │
                                                              ▼
                                                    Epic 3 Identity (gate)
                                                              │
        ┌──────────────────────┬──────────────────┬──────────┴────────┐
        ▼                      ▼                  ▼                   ▼
  Epic 4 Metadata ──► Epic 5 Upload ──► Epic 6 Transcoder ──► Epic 7 Event wiring
                                                                      │
                                                                      ▼
                                                              Epic 8 Playback
                                                                      │
                                                                      ▼
                                                          Epic 9 Production + promotion
                                                                      │
                                                                      ▼
                                                          Epic 10+ Enrichment (backlog)
```

The core loop (4→5→6→7) is split into separately-testable layers on purpose: data, then upload-front-half, then transcoder-in-isolation, then the wiring that connects them. When the loop misbehaves, you already know which layer works.

## Epics & sprints

### Epic 0 — Foundations (repo, local scaffold, walking skeleton)
- ✅ 0.1 Repo + branches + protection — public repo at github.com/rklundt/SLAYList; CodeQL retry deferred to 0.2
- ✅ 0.2 Monorepo scaffold + shared types skeleton — pnpm 11.3.0 (D34 supersedes D18's npm pin); CodeQL retry pending post-merge of this PR
- ⬜ 0.3 Local run (frontend + API "hello") with one command
- ⬜ 0.4 Foundational docs + verify slash-commands wired
- **Exit:** clone, one command, see the app locally. No Azure.

### Epic 1 — Azure landing zone (dev resources)
- ⬜ 1.1 Resource group + naming + budget alert ($15/mo) + Application Insights (D24)
- ⬜ 1.2 Dev Static Web App (Free tier per D26)
- ⬜ 1.3 Dev storage account (blobs + table) — captures connection string for SWA API (D25)
- ⬜ 1.4 Dev Container App environment — with Managed Identity + storage RBAC (D25)
- ⬜ 1.5 Dev Event Grid + queue
- **Exit:** dev resources exist in portal. Not wired together.

### Epic 2 — Pipeline (dev, on the skeleton)
- ⬜ 2.1 Deploy credentials + GitHub secrets
- ⬜ 2.2 Actions workflow: build + deploy frontend/API to dev SWA on push to `develop`
- ⬜ 2.3 Run it, fix first-deploy errors
- **Exit:** push to `develop` auto-deploys skeleton to dev; loads on the internet.

### Epic 3 — Identity (Entra + roles, the gate)
- ⬜ 3.1 Entra app registration + define 3 roles (human-guided)
- ⬜ 3.2 Shared family account + role assignment
- ⬜ 3.3 Wire SWA auth; API reads role from token
- ⬜ 3.4 Login gate + "your role is X" proof
- **Exit:** log in on deployed dev app; it knows your role.

### Epic 4 — Metadata model & song records (no audio)
- ⬜ 4.1 Table Storage schema + shared `Song` type + states; **harden CI test gate soft→hard (D23)**
- ⬜ 4.2 API: create/read/list/update records
- ⬜ 4.3 Barebones "list all songs" screen from seeded fake records
- ⬜ 4.4 Nightly Table Storage backup job (D33) — tables have no native versioning
- **Exit:** app lists songs from real metadata; no audio yet; nightly metadata backups running.

### Epic 5 — Upload & raw storage (no transcoding)
- ⬜ 5.1 Input validation (allowlist + size cap) — decide specifics
- ⬜ 5.2 Upload UI + API endpoint → raw blob + `processing` record
- ⬜ 5.3 Role enforcement (uploader/admin only)
- **Exit:** upload lands raw file + `processing` record; stays processing.

### Epic 6 — Transcoder container
- ⬜ 6.0 Container image build/push/deploy pipeline (placeholder container) — *prove the plumbing before 6.1 lands real logic*
- ⬜ 6.1 ffmpeg transcode logic (raw → Opus/AAC, write finished, flip record, `failed` on error)
- ⬜ 6.2 Containerize with ffmpeg in image
- ⬜ 6.3 Build/push image, deploy to dev Container App (*may simplify or fold into 6.2 once 6.0 exists — Epic 6 planning decides*)
- **Exit:** hand the container a raw file → finished song + updated record (manual trigger).

### Epic 7 — Event wiring
- ⬜ 7.1 Blob-created → Event Grid → queue
- ⬜ 7.2 Container App scales from zero on queue; retry + dead-letter → `failed`
- ⬜ 7.3 End-to-end test through the UI
- **Exit:** upload via UI → processing → ready automatically.

### Epic 8 — Playback & listener experience
- ⬜ 8.1 Audio player + serve-from-finished-blob
- ⬜ 8.2 Browser/Cache-API local caching (egress saver + PWA groundwork)
- ⬜ 8.3 Mobile-first polish
- **Exit:** kids log in and play their songs on a phone.

### Epic 9 — Production environment & promotion
- ⬜ 9.1 Create prod resources (separate accounts/queue/Container App; SWA prod env)
- ⬜ 9.2 Extend pipeline: `main` → prod
- ⬜ 9.3 First promotion + prod smoke test
- **Exit:** clean dev→prod flow; kids use prod URL.

### Epic 10+ — Enrichment
- ⬜ Pull from `docs/BACKLOG.md` as prioritized: playlists, search, admin tools, deactivate UI, budget tuning, PWA manifest polish, custom domain, then (much later) Android wrapper, CDN, DB upgrade, multi-library (D19/D20).
