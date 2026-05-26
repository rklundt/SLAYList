# CLAUDE.md — Read this first, every session

This file is the entry point for any AI or human developer working on this project. If you are Claude Code starting a session, read this file, then `docs/ARCHITECTURE.md`, then the current sprint file, before writing anything.

## The doc map (read these to orient)

Active during every session — read in this order on session start:

- **`CLAUDE.md`** (this file) — guardrails + entry point
- **`docs/ARCHITECTURE.md`** — the settled design (the diagram + component reasoning)
- **`docs/DECISIONS.md`** — D1–DN, why everything is the way it is, what alternatives were rejected (supersede-in-place pattern; never silently rewritten)
- **`docs/DEVELOPER_GUIDE.md`** — practical "how to work on it" (public-repo hygiene rules, Node version policy, logging discipline, storage auth posture, filesystem requirements)
- **`docs/VERSIONS.md`** — pinned versions, dated runtime-verification trail (the place to check before bumping Node/deps/runtime, and to record new pins)
- **`docs/BACKLOG.md`** — "Deferred by design," "Open questions to resolve at the right epic," "Emergent" — consult before assuming a problem is novel
- **`.sprints/INDEX.md`** — epic/sprint map + status (✅/🟡/⬜); the dependency-shape diagram is here

When relevant to the current task:

- **`.sprints/epic-N-<name>/SPRINTS.md`** — the current epic's sprint file with user stories + acceptance criteria
- **`.claude/commands/{start-sprint,wrap-sprint,close-sprint}.md`** — the slash-command bodies (contain the STOP CHECK for `/wrap-sprint` and the Phase A/B split for `[Human, guided]` sprints)
- **`infra/`** — canonical home for naming convention (`naming-convention.md`), gitignored real-values notes (`dev-resources.md`, `prod-resources.md`), and future restore-procedure runbooks. NOT `docs/infra/` — the canonical location is at repo root per Sprint 0.2 / `docs/DEVELOPER_GUIDE.md` repo layout
- **`docs/guides/<sprint>-*.md`** — sprint-specific human walkthroughs (only when a `[Human, guided]` sprint needs portal steps)

Public-repo meta (rarely change but live during the project):

- **`LICENSE`** — AGPL-3.0-or-later (FSF verbatim text)
- **`CONTRIBUTING.md`** — DCO + relicensing grant; sign-off mechanics (`git commit -s`)
- **`SECURITY.md`** — private vulnerability reporting + explanation of the residual dev-only Dependabot alerts so a casual repo browser doesn't read "19 open alerts" as neglect
- **`README.md`** — newcomer quickstart (Node version, `pnpm install`, `pnpm dev`); audience overlap with this file is small

If a path above doesn't exist yet, it's because the relevant sprint hasn't created it — don't assume it should already exist.

## What this project is

A private, login-gated web app where a family's kids upload songs they made (with AI tools like Suno) and play them back on their phones, tablets, and laptops. It is **not** a commercial product, not for public sharing, not for sale. Think "private family music library that happens to live on the internet."

**The app is private; the source code is public.** This repository is public from its first commit, licensed AGPL-3.0-or-later (see `LICENSE`, D15, D17). Do not conflate the two. The repo being public means: no secrets, no real Azure resource names, no family-identifying detail (kid names, addresses, etc.) ever lands in a committed file. The login gate protects the app; commit hygiene protects the family.

The original goal, in the owner's words: *let my kids have fun making songs and hearing them on their device from the internet.* Every decision should be checked against that. When in doubt, favor simple and cheap over scalable and clever — but do not foreclose the documented growth paths (see ARCHITECTURE.md "Deferred / growth").

## The single most important rule

**Do not silently make architectural decisions.** This project was designed through a long, careful conversation. The decisions in `docs/ARCHITECTURE.md` and `docs/DECISIONS.md` are deliberate and have reasons. If a sprint tempts you to contradict one (e.g. "it'd be easier to just store the metadata in the JSON file" or "let's put dev and prod in one storage account"), STOP and flag it to the human with the tradeoff. Many of these exact temptations were already considered and rejected for documented reasons.

## How work is organized

- Work is grouped into **Epics** (like phases), each in `.sprints/epic-N-name/`.
- Each epic contains **Sprints**, each a markdown file with user stories and acceptance criteria.
- `.sprints/INDEX.md` is the high-level map of all epics/sprints and their status. It is kept current by `/close-sprint`. Use it to reason about downstream impact of a change.
- Three slash commands drive the loop: `/start-sprint`, `/wrap-sprint`, `/close-sprint`. See `.claude/commands/` (Claude Code's expected location — moved from `.commands/` in pre-Epic-0 alignment so the commands are actually loaded by the CLI).

## The development loop (how a sprint goes)

1. `/start-sprint <epic>/<sprint>` — re-establish context, review existing code, plan the work.
2. Build the sprint's user stories.
3. `/wrap-sprint` — five-perspective review (sr dev, solution architect, devops, infosec, support). Findings are rated critical/moderate/low. **Critical findings block the recommendation to proceed.** Human decides what to fix.
4. `/close-sprint` — prepare the PR to `develop`, update docs and INDEX if the sprint changed anything, surface (do NOT auto-resolve) merge conflicts. **The human performs the actual merge.**

## Hard guardrails (do not violate without explicit human approval)

- **License is AGPL-3.0-or-later (D15).** Every source file you create — TypeScript, JavaScript, Dockerfiles, shell scripts, YAML workflows, CSS — opens with a two-line header in the language's comment syntax:
  ```
  Copyright (c) <current-year> Ray Klundt
  SPDX-License-Identifier: AGPL-3.0-or-later
  ```
  Pure-data files (`package.json`, `tsconfig.json`, lockfiles, `.gitignore`, `LICENSE` itself) are exempt — no comments possible or appropriate. Markdown docs are also exempt. `/wrap-sprint` flags missing headers on files that should have them.
- **AGPL § 13 source-link obligation.** Once the app has a user-visible UI (Epic 0.3 onward), it must include a visible link to the source repository so network users can obtain corresponding source. A footer link is enough. Do not ship a UI without it.
- **Contributor terms are DCO + relicensing grant (D16).** All commits in PRs need `Signed-off-by`. Use `git commit -s`. PRs without sign-off don't merge.
- **No local password auth, ever.** Identity is Entra ID. Roles (listener/uploader/admin) ride in the token; the API enforces them on every request.
- **No deployed environment is ever reachable on the public internet without authentication in front of it — from the very first deploy, in every environment (D22).** This is a runtime invariant, not a sequencing rule (D11 is the sequencing rule; D22 is the deployed-state rule). It applies to dev (Epic 2), prod (Epic 9), and any later environment. Epic 2's mechanism is a `staticwebapp.config.json` route gate using SWA's pre-configured Microsoft (AAD) provider; Epic 3 strengthens it by swapping the redirect target to a custom Entra app registration. The gate is never absent; it only evolves.
- **Until Epic 3's role-based authorization is live, no environment may serve anything beyond the trivial skeleton (D22 corollary, time-bounded).** The Epic-2-era gate is authentication-only via the pre-configured AAD provider and trusts *any* Microsoft account — it is NOT family-restricted. So no song data, no upload, no real content, no listable lists of anything meaningful may ship behind it. Allowed surface in the Epic 2 → Epic 3 window: the "hello world" page and a trivial `/api/health` endpoint. **When Epic 3.4 lands, this bullet is *superseded in place* (rewritten from active prohibition to historical note via `/close-sprint`), NEVER silently removed.** The parent invariant above remains active forever. Self-deleting guardrails are a foot-gun: a sprint could be marked done while the substitution didn't fully take, leaving a weak gate behind without the protective rule still in view. Supersession-in-place matches how `docs/DECISIONS.md` entries are handled (D12 → D19 pattern) — the reasoning survives, the rule's history is visible, and no conditional-removal machinery exists to misfire.
- **Never expose a feature without the role check in front of it.** Auth (Epic 3) lands before features for this reason.
- **Authorization is always library-scoped (D20).** Every authz check asks "can this person act *within this `libraryId`*", never "can this person act globally." There is one library today (`'slaylist-home'`); never write code that assumes one library OR that grants cross-library reach. The two-tier admin model (library admin vs. platform/global admin) is a *documented future addition* (D20), not built now — do not add a global/platform admin role today.
- **Dev and prod data stores are physically separate** (separate storage accounts, separate queues, separate Container Apps). Compute/routing can be logically split; anything holding data cannot. Reason: blast radius — a dev mistake must never be able to touch the kids' real songs.
- **The metadata store is Azure Table Storage**, not a shared JSON file. (A JSON file was considered and rejected — see DECISIONS.md, it creates a whole-catalog write-lock problem.)
- **The blob filename is plumbing; the song title lives in metadata.** Filenames are `{title-slug}_{timestamp}_{shortid}.{ext}` for human-readability during restore, but uniqueness is guaranteed by the short id, never the timestamp.
- **Transcoding is async via the event chain** (blob → Event Grid → queue → Container App). The API never transcodes inline.
- **Secrets never live in code or in the repo.** They live in GitHub Actions secrets and Azure configuration. **For Azure deploy auth specifically, use OIDC federation (D30)** — no long-lived service-principal client secret stored in GitHub Secrets. Runtime app→storage auth follows D25's split posture (connection string for SWA managed-functions API; Managed Identity for the Container App).
- **No PII in logs (D32).** Log `ownerOid` (opaque), NEVER `ownerDisplayName` (Entra `preferred_username` — email/handle, PII per D21). Log `songId`, NEVER `title` (kids put real names in song titles). For the transcoder specifically: do not let ffmpeg's stderr — which embeds the input filename — flow unsanitized to Application Insights; use songId-based local filenames during transcode OR substitute filename→songId in captured stderr before emitting. App Insights data is indexed, queryable, and hard to selectively remove — the rule must hold *before* the first log line. `/wrap-sprint` InfoSec verifies.
- **Raw uploads are the canonical archive — never delete them (D28).** The `raw-uploads` blob area holds the kids' actual creations; transcoded copies are derivative and can be regenerated, originals cannot. No lifecycle rule, cleanup job, or "since song is `ready`, the raw is unneeded" pruner ever deletes from `raw-uploads`. Tier-transition lifecycle rules (Hot → Cool → Archive) are fine; deletion-class rules are forbidden.
- **The human merges. Claude Code prepares merges.** Never auto-resolve merge conflicts.
- **Branch pushed ≠ sprint done. /wrap-sprint cannot begin until every acceptance criterion is confirmed complete.** Before recommending /wrap-sprint (or any next-step that assumes the sprint is finished), restate each acceptance bullet from the sprint file as ✅ done / ⬜ pending with one-line evidence (commit hash, file path, or human attestation). If any bullet is pending — including human-executed ones for `[Human, guided]` sprints — STOP and tell the human what's left. Do not advance. This rule exists because the failure mode is silent: a sprint branch with Phase A work committed *looks* like a finished sprint, and the conversation can drift to /wrap-sprint with Phase B's human-executed acceptance bullets still pending and unverified. The restate-as-checklist discipline makes that impossible to miss.
- **Public-repo hygiene applies at write time, not just /wrap-sprint review.** The rules in `docs/DEVELOPER_GUIDE.md` "Public-repo hygiene" (no secrets, no real personal email addresses, no real Azure resource identifiers beyond the generic project prefix, no GUIDs / connection strings / deployment tokens, no family-identifying detail) are **write-time** constraints. Before writing any file that would include such a value, use a placeholder (`<your-email@example.com>`, `<connection-string>`, etc.) and capture the real value in the gitignored local notes (`docs/infra/dev-resources.md`, etc.). /wrap-sprint InfoSec is the backstop, not the primary defense — by the time it runs, a leak is already in `git log` on a public repo, which is forever.

## Tech stack (see ARCHITECTURE.md for the why)

- Frontend + light API: Azure **Static Web App**, React + TypeScript (Vite). API is TypeScript too — one language across the repo.
- Audio storage: Azure **Blob Storage** (raw-uploads area + finished area), soft-delete + versioning on.
- Metadata: Azure **Table Storage**.
- Transcoder: Azure **Container App** running ffmpeg, scale-to-zero, triggered by a queue.
- Eventing: **Event Grid** → **queue** (Storage Queue to start; Service Bus only if outgrown).
- Identity: **Entra ID**, three roles.
- Audio format: **Opus** (or AAC for max device compatibility) — decided per ARCHITECTURE.md.

## Conventions

- TypeScript everywhere. Shared types between API and frontend live in a shared location so a `Song` means the same thing on both sides.
- Mobile-first, touch-friendly layout (this becomes a PWA, and later possibly an Android wrapper — don't fight that path).
- Every song record carries a `libraryId` field even though we are single-library now (D19, supersedes D12). Never write code that assumes one library. (Multi-library is deferred, not designed-out.) Today's value is `'slaylist-home'`. **Not** the Entra tenant ID — that is an Azure concept, kept separate by name.
- Keep the audio cacheable by the browser (correct cache headers) — repeat plays should not re-hit Azure. This is the main egress saver.
