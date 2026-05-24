# Epic 0 — Foundations

**Goal:** A near-empty app runs locally and the repo is real. No features, no Azure. This epic exists so everything after it stands on solid ground, and so the pipeline (Epic 2) has a trivial "walking skeleton" to prove itself on.

**Exit criterion:** clone the repo, run one command, see the app locally.

---

## Sprint 0.1 — Repo, branches, protection
**[Human]** (Claude Code writes the step-by-step guide first, performs the hygiene scan, and prepares `.gitignore` + the initial commit content; the human creates the GitHub repo and executes the push.)

User stories:
- As the owner, I want a **public** GitHub repo (AGPL-3.0-or-later per D15/D17) so the source is openly available from commit one — while the running app stays private (login-gated, Epic 3).
- As the owner, I want `main` and `develop` branches so I can later deploy prod from `main` and dev from `develop`.
- As the owner, I want branch protection on `main` (PR required, no direct push) so prod can't be changed casually.
- As the owner, I want the first commit to be already-clean — no secrets, no real Azure resource names, no family-identifying detail — because the history is permanent once pushed to a public repo.

Acceptance:
- **Hygiene scan** of the scaffold contents complete: no secrets, tokens, real resource names, real personal/kid detail, or real email addresses (other than the maintainer's copyright line) anywhere in the working tree. Findings recorded; everything resolved before `git init`.
- **`.gitignore`** present at the repo root and reviewed against the public-repo hygiene rules in `docs/DEVELOPER_GUIDE.md`. Covers: Node (`node_modules/`, `dist/`, `.vite/`), env/secret patterns (`.env`, `.env.*`, `local.settings.json`, `*.pem`, `*.key`), editor/OS noise (`.vscode/`, `.idea/`, `.DS_Store`, `Thumbs.db`), Azure Functions Core Tools local state, Static Web Apps CLI artifacts, and **Claude Code per-user local state** (`.claude/settings.local.json` — already exists in the working tree; this file holds local permission grants and must not be committed; `.claude/commands/` and `.claude/settings.json` are repo-shared and DO get committed). Pinned via `git status` confirming nothing sensitive is staged.
- **Public** GitHub repo exists (deliberate "Set visibility: Public" step in the guide); `main` and `develop` both present; `develop` is the default working branch.
- Branch protection on `main` (and ideally `develop`): PR required, no direct pushes.
- **Public-repo GitHub security baseline enabled (D31)**: secret scanning ON, **push protection ON** (the critical control — blocks secrets at `git push` before they reach GitHub), Dependabot security updates ON, CodeQL code scanning ON (default config). All free on public repos; not enabling them is a partial implementation of D17.
- **Post-push secret-scanning verification (IS-4):** immediately after the first push, run `gh secret-scanning alert list` (or check Security tab in the GitHub UI) to confirm zero alerts. If anything flagged, rotate immediately and remove from history per the 0.1 guide's "If something goes wrong" section.
- This scaffold's files (post-hygiene-scan) are committed to `develop` as the first commit. Commit is signed off (`git commit -s`) per D16.

Notes: Claude Code produces `docs/guides/0.1-repo-setup.md` with exact clicks/commands (including the deliberate "set visibility to Public" step); the human executes repo creation and push. Claude Code does NOT run `gh repo create` — repo creation and visibility are account-level decisions the owner makes, and this sets the right precedent for the Azure portal steps in Epic 1.

## Sprint 0.2 — Monorepo scaffold + shared types skeleton
**[Claude Code]**

User stories:
- As a developer, I want the repo folders (`/frontend`, `/api`, `/transcoder`, `/shared`, `/infra`, `/.github/workflows`) so each concern has a home.
- As a developer, I want a `/shared` types module (even if near-empty) so `Song`, roles, and states are defined once and imported by frontend, api, and transcoder.

Acceptance:
- Folder structure matches `docs/DEVELOPER_GUIDE.md` layout.
- `/shared` exports placeholder types: `Song`, `SongState` (`processing|ready|failed|deactivated`), `Role` (`listener|uploader|admin` — locked spelling/casing). `libraryId` present on `Song` (D19, supersedes `tenantId` from D12); `ownerOid` + `ownerDisplayName` + optional `createdByKid` per D21; `format` typed as `string` for now with a `// TODO(Epic 6): narrow to a union once output format is chosen` comment near it.
- **Vitest is wired up (D23)** at the root and per-workspace: `pnpm test` (which delegates via `pnpm -r run test` per D34) runs Vitest across `/shared`, `/frontend`, `/api`, and `/transcoder` workspaces; a placeholder `*.test.ts` in `/shared` proves a test can run and pass. CI integration lands in Epic 2 (soft mode until Epic 4.1 hardens it).
- **TypeScript strict mode pinned at root (D29):** root `tsconfig.json` has `"strict": true` and `"noUncheckedIndexedAccess": true`. All workspaces extend the root via `"extends": "../tsconfig.json"`. No workspace silently overrides these two flags downward. Verified by running `tsc --noEmit` across all workspaces.
- **Re-attempt CodeQL default-setup (D31, deferred from Sprint 0.1).** Once TypeScript code is present in `/shared` (or any workspace), enable in the GitHub UI (Security → Code scanning → Set up → Default) OR via `gh api -X PATCH repos/rklundt/SLAYList/code-scanning/default-setup --input <{"state":"configured","query_suite":"default"}>`. Verify configured: `gh api repos/rklundt/SLAYList/code-scanning/default-setup --jq '.state'` returns `"configured"`. If still 404 or fails with a different error, escalate as a Sprint-0.2 finding rather than silently dropping D31's CodeQL requirement. **(Note from Sprint 0.2 post-merge: the correct HTTP verb is `PATCH`, not `PUT` as initially documented. Earlier attempts used PUT and got 404s for two reasons compounded — first the markdown-only repo had no language to scan, then the verb was wrong. PATCH against a TS-containing default branch succeeds. Documented in D31's resolution note.)**
- Frontend and API both successfully import from `/shared`.

## Sprint 0.3 — Local run (one command)
**[Claude Code]**

User stories:
- As a developer, I want one command to run the frontend + API locally so I can see "it works" before any Azure exists.

Acceptance:
- A documented single command starts frontend + API locally.
- Frontend shows a trivial "SLAYList — it works" page **with an AGPL source-link footer pointing at the public repo URL** (satisfies the AGPL § 13 guardrail in `CLAUDE.md` from the first runnable UI — every later UI sprint inherits this footer; never ship a UI without it).
- API exposes a trivial health endpoint the frontend calls and displays.
- Node version pinned; recorded in `docs/VERSIONS.md`.

## Sprint 0.4 — Foundational docs + verify commands wired
**[Both]**

User stories:
- As a future developer, I want the docs (CLAUDE, ARCHITECTURE, DECISIONS, DEVELOPER_GUIDE) present and accurate so I can onboard.
- As the owner, I want the three slash-commands actually recognized by Claude Code in this environment before relying on them.

Acceptance:
- Docs present (they are, from scaffold) and reviewed against the actual scaffold for accuracy.
- `README.md` quickstart written.
- **Slash-command location verified and invokable.** Claude Code loads project slash commands from `.claude/commands/*.md` (not `.commands/`); the three files were moved there during pre-Epic-0 alignment. This sprint confirms `/start-sprint`, `/wrap-sprint`, `/close-sprint` are actually invokable in this environment after the move — a smoke-test, not a guess.
- `.sprints/INDEX.md` reflects Epic 0 as done at sprint's end.

---

### Reviewer focus for this epic (used by /wrap-sprint)
- **Infosec:** repo is **public** (D17) and AGPL-licensed; the *app* is private (login-gated, Epic 3) — verify nothing in the initial commit conflates the two. No secrets, no real Azure resource names, no family-identifying detail committed. `.gitignore` covers local config and Azure tooling local state.
- **DevOps:** branch protection actually on; `develop` default.
- **Solution architect:** folder layout and shared-types match the documented architecture; nothing pre-bakes a single-library (D19) or local-password (D2) assumption, and no authz logic assumes global cross-library reach (D20).
- **Sr dev:** one-command local run genuinely works on a clean clone.
- **Support:** README is followable by someone who isn't you.
