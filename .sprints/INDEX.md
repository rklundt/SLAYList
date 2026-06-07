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
**Status: ✅ DONE.** Clone the repo, `pnpm install`, `pnpm dev`, browse `http://localhost:5193` — the walking skeleton runs locally end-to-end. No Azure resources yet (those start at Epic 1).
- ✅ 0.1 Repo + branches + protection — public repo at github.com/rklundt/SLAYList; CodeQL retry deferred to 0.2
- ✅ 0.2 Monorepo scaffold + shared types skeleton — pnpm 11.3.0 (D34 supersedes D18's npm pin); CodeQL configured post-merge via PATCH (D31 baseline 4/4)
- ✅ 0.3 Local run (frontend + API "hello") with one command — 4-process `pnpm dev` stack (Azurite + tsc-watch + func + Vite); D35 (Azurite); 12 tests passing
- ✅ 0.4 Foundational docs + verify slash-commands wired — doc-accuracy sweep (clean; minor README/INDEX drift fixed); /start-sprint, /wrap-sprint, /close-sprint all proven invokable through active use across Epic 0's sprints (every sprint produced signed-off PRs merged to develop)
- **Exit:** clone, one command, see the app locally. No Azure. ✅ Met.

### Epic 1 — Azure landing zone (dev resources)
**Status: ✅ DONE.** Every dev Azure resource (RG, LAW + App Insights + budget, SWA, storage with containers/table/queues/diagnostics, Container App env + app + MI + RBAC, Event Grid system topic) exists in the portal AND is captured as env-neutral Bicep under `infra/bicep/` (D39), validated two ways (throwaway-RG deploy + `what-if` against live dev) at Sprint 1.6. Exit criterion met at 1.6. Sprint 1.7 (✅ done) reconciled the live dev RG to `managed-by=bicep` and added a read-only drift detector (`infra/bicep/drift-check.ps1`) — optional tidiness that did NOT gate Epic 1 closure or Epic 2.
- ✅ 1.1 Resource group + naming + budget alert ($15/mo) + Application Insights (D24) — dev only; prod mirror at Sprint 9.1. D36 (public network access stays enabled) recorded.
- ✅ 1.2 Dev Static Web App (Free tier per D26) — `swa-music-slaylist-dev-use2`, empty deploy target (Deployment source = `Other`, D22 safeguard verified); D37 (OIDC-primary deploy auth + break-glass token) added
- ✅ 1.3 Dev storage account (blobs + table) — `stmusicslaylistdevuse2`; `raw-uploads`/`finished`/`table-backups` containers + `Songs` table; 30d soft-delete + versioning; **D28 invariant verified empty**; Storage Diagnostics → LAW wired and verified end-to-end; D38 (public-access posture) added
- ✅ 1.4 Dev Container App environment + placeholder Container App — `cae-music-slaylist-dev-use2` hosting `ca-music-slaylist-dev-use2`; system-assigned MI + 2 storage RBAC roles per D25's cleaner half; **D25 invariant verified** (no connection string anywhere on the app); MI runtime verification deferred to Sprint 6.1 per D37-shape precedent
- ✅ 1.5 Dev Event Grid + queue — `egst-music-slaylist-dev-use2` system topic with MI + `transcode-jobs` + `transcode-jobs-poison` queues in `stmusicslaylistdevuse2`; D24 third storage-service feeder leg (`diag-queue-to-law-dev`) + fourth overall (`diag-egst-to-law-dev`); Sprint 7.1 acceptance expanded for subscription + RBAC + end-to-end verification (`_test-event-trigger-*` naming convention per D28 implementation note)
- ✅ 1.6 IaC capture (Bicep) — all Sprint 1.1–1.5 resources captured as env-neutral Bicep modules under `infra/bicep/`; prod (Sprint 9.1) is a parameter-substitution deploy, future infra changes go through reviewable PRs. Validated **two ways**: deploy-to-throwaway-RG + `az resource list` comparison, AND `az deployment group what-if` against live dev (caught 6 Phase-A capture gaps incl. a blob soft-delete retention that would have shrunk the recovery window, and a wrong RBAC role Queue→Table). Non-sensitive outputs only — secrets fetched post-deploy, never emitted (D39). D39 records the choice + two-pass posture + what-if interpretation notes; **D40** records the conscious interim posture on storage-diagnostic-log PII (categories stay ON, tripwire before Epic 5). CLAUDE.md guardrail added: Bicep is the infra source of truth, kept in sync every sprint.
- ✅ 1.7 Reconcile live dev RG to Bicep (**was optional; did NOT block Epic 1 or Epic 2**) — applied the Bicep to the live `rg-music-slaylist-dev-use2`; dev now carries `managed-by=bicep` + `region` tags. Handled the role-assignment-409 caveat (deleted dev's 2 portal-created assignments first; redeployed with deterministic GUIDs). Verified data/retention untouched (D7/D28), D25 still holds (empty Container App env). Added `infra/bicep/drift-check.ps1` + `.bat` (read-only `what-if`-based drift detector: CLEAN/DRIFT verdict, always-shown REVIEW note for what-if-opaque props, `-ShowNoise` audit) and `.gitattributes` EOL policy. Deleted the empty auto-created Smart Detection action group (gitignored-notes attestation). CI-automated drift check backlogged for Epic 2.
- **Exit:** dev resources exist in portal AND are captured as IaC; manual-portal scope ✅ at Sprint 1.5; IaC capture closed at Sprint 1.6; live dev brought under Bicep management at Sprint 1.7.

### Epic 2 — Pipeline (dev, on the skeleton)
**Status: ✅ DONE.** Push to `develop` auto-deploys the gated skeleton to dev Azure via OIDC (no stored secret); the deployed dev URL is auth-gated from the first deploy (D22 — anonymous redirected to Microsoft sign-in) and, signed in, serves the "SLAYList — it works" page + a working `/api/health` (200). Exit criterion met at Sprint 2.3.
- ✅ 2.1 Deploy credentials (OIDC federation, D30/D37) — provisioned by `scripts/bootstrap-deploy-identity.ps1`, a committed idempotent **bootstrap script** (D41: not Bicep — Graph plane + bootstrap credential; not manual — audit + prod-repeatability). Created the Entra deploy app `slaylist-github-deploy-dev` (**separate app per env**, D7 two-app model) + `develop` federated credential (no client secret) + dev-RG-only Contributor + **5 GitHub secrets** (3 OIDC IDs stored as secrets not variables for public-repo log-masking — D30 note; + storage & App Insights connection strings). SWA deploy token NOT in secrets (D37); `gh variable list` empty. Bonus: Container App CPU/mem/maxReplicas parameterized for prod sizing (dev unchanged, drift-check CLEAN). Least-privilege custom role backlogged.
- ✅ 2.2 Actions workflow (`.github/workflows/deploy-dev.yml`): test job (Vitest, soft-mode per D23) + build-and-deploy. pnpm build in CI, Oryx bypassed (D34); `azure/login` OIDC + `pnpm exec swa deploy` with the deploy token fetched at runtime + masked, never in Secrets (D37); D22 gate ships in `staticwebapp.config.json`; D24/D25 connection strings wired to SWA app settings.
- ✅ 2.3 First deploy + verify: gated skeleton live on the dev SWA. Anonymous → Microsoft sign-in redirect (page, API, **and** JS assets all 302); signed-in → page renders + `/api/health` returns 200. Six first-deploy fixes documented in `docs/DEPLOYMENT_FLOW.md`; the load-bearing one = a **flat `node_modules`** so SWA registers the managed function (pnpm symlinks don't survive the deploy zip → 0 functions, silently). `@azure/functions` pinned exact `4.16.0`.
- **Exit:** push to `develop` auto-deploys the gated skeleton to dev; loads on the internet behind auth. ✅ met at 2.3.

### Epic 3 — Identity (Entra + roles, the gate)
- ✅ 3.1 Entra app registration + define 3 roles (human-guided) — `slaylist-auth-dev` (per-env, D42) created by `scripts/bootstrap-auth-app.ps1`: three app roles `listener`/`uploader`/`admin` (values match `shared` `ROLES`; D20 single admin), single-tenant + `appRoleAssignmentRequired=true`. SP auto-tagged for default Enterprise Apps visibility. Client secret + redirect URI + SWA wiring + the D22 gate swap deferred to 3.3 (gate untouched this sprint). appId/tenantId in gitignored notes.
- ✅ 3.1.5 Security triage **(inserted/emergent)** — assessed all 23 open Dependabot alerts; every one `scope=development` (transitive deps of `azurite` + `@azure/static-web-apps-cli`, never deployed — D7). Patched the fixable family (axios SSRF/cred-leak/proto-pollution set, tmp, @azure/identity, tough-cookie, xml2js) via selector-scoped, exact-pinned `overrides` in `pnpm-workspace.yaml`, verified not to break the dev stack (build, tests, azurite blob/queue/table round-trips). `uuid` left at azurite's required version (its fix removed the `uuid/v4` subpath ms-rest-js uses) — dev-only + unreachable, dismissed in GitHub with reason. Triage + override-maintenance policy in `SECURITY.md`.
- ✅ 3.2 Shared family account + role assignment (human-guided) — created the family Entra accounts (Model A, D2) + assigned app roles on `slaylist-auth-dev`: an `uploader` account and a dedicated `admin` account (the owner's personal account deliberately **not** assigned — kept out of the app). Implemented as a per-kid member account rather than a single shared login (the data model supports it; the deferred guest-invite per-kid path in BACKLOG is unaffected). Portal-guided per `docs/guides/3.2-family-account-role.md`; real UPNs/passwords in gitignored notes only. No deploy / no gate change — actual sign-in starts at 3.3.
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
