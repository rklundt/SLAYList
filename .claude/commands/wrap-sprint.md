---
description: Five-perspective skeptical review of the sprint's work. Rates findings critical/moderate/low. Critical findings block the recommendation to proceed.
---

# /wrap-sprint

Review the work completed in this sprint from five independent, skeptical perspectives. Your job is to FIND PROBLEMS, not to reassure. A review that finds nothing is suspect — look harder. Do not rubber-stamp.

## STOP CHECK — before running the five reviewers

Before any reviewer perspective runs, walk the sprint's acceptance criteria as a checklist. Reviewing half-done work produces noise and false confidence — this check makes sure the work being reviewed is *actually* complete.

1. Open the sprint file (`.sprints/epic-N-<name>/SPRINTS.md` or the individual sprint file under that epic).
2. List each acceptance bullet from the target sprint.
3. Mark each ✅ done / ⬜ pending with one-line evidence:
   - ✅ done: cite the commit hash, file path, or human attestation
   - ⬜ pending: state precisely what's missing
4. For **[Human, guided]** sprints (or **[Both]** sprints with a human portion), explicitly require human attestation of the Phase B (manual / portal / human-executed) work. The human's attestation IS the evidence; absence of it = pending. Do not assume Phase B happened because Phase A is committed; the two phases complete independently.

**If any acceptance is pending, STOP.** Do not run the five reviewers below. Tell the human exactly what's left to complete and how to verify it. The five-perspective review evaluates *completed work*; running it on a half-done sprint wastes everyone's time and risks blessing a sprint that isn't actually done.

This check is the matching enforcement for the CLAUDE.md guardrail "Branch pushed ≠ sprint done." It catches the exact silent failure mode where Phase A's commit makes the sprint *look* done while Phase B's acceptance bullets are still pending.

Only after the checklist is fully ✅ does the five-reviewer pass below run.

## The five reviewers

Run each as a distinct perspective with its own checklist. For each, list concrete findings (file/line or specific behavior), each rated **CRITICAL / MODERATE / LOW**.

### 1. Senior Developer
- Correctness, edge cases, error/failure paths actually handled (no stuck `processing`, no orphaned blobs/records).
- Idempotency where relevant; duplicate-delivery safety.
- Shared types are the single source of truth; no divergent shapes.
- Dead code, copy-paste, missing tests on the risky paths.

### 2. Solution Architect
- Does this contradict anything in `docs/ARCHITECTURE.md` or `docs/DECISIONS.md`? Name the entry.
- Did a rejected alternative sneak in (JSON-file metadata D3, inline transcode D5, shared dev/prod data store D7, local passwords D2)?
- Did anything bake in a single-library assumption (D19, superseding D12), or assume global cross-library reach in authz (D20), or block a documented growth path (D13 PWA, search/playlists)?

### 3. DevOps
- Secrets only in GitHub secrets / Azure config — never in repo or logs.
- Config parameterized dev vs prod; no hardcoded environment.
- Deploy/build reproducible; failures observable; scale-to-zero preserved where it should be.
- Dead-letter / retry paths exist and are monitorable (Epic 7+).

### 3b. Licensing & provenance (per D15/D16)
- Every new source file (`.ts`, `.tsx`, `.js`, `.mjs`, `.cjs`, `.css`, `.scss`, `.sh`, `.ps1`, `.dockerfile`/`Dockerfile`, `.yml`/`.yaml` workflow) starts with the two-line SPDX header:
  `Copyright (c) <year> Ray Klundt` + `SPDX-License-Identifier: AGPL-3.0-or-later`. Missing header = **MODERATE** finding (CRITICAL if a whole new module ships headerless).
- Pure-data files (`package.json`, `tsconfig*.json`, lockfiles, `.gitignore`, `.env*`, `LICENSE`) and markdown docs are exempt.
- If this sprint produces user-visible UI, confirm an AGPL § 13 source link is present (footer link to the public repo). Absent link on a shipped UI = **CRITICAL**.
- All commits on the sprint branch carry `Signed-off-by` (D16). Missing sign-off = **CRITICAL**. Per `CONTRIBUTING.md`, PRs without sign-off do not merge — the absence of sign-off is a blocking defect, not advisory. `/close-sprint` will refuse to push a branch with any unsigned commit; flagging it here is the earlier checkpoint.

### 4. InfoSec
- **D22 invariant (every sprint that deploys anything):** is the deployed environment reachable by an anonymous browser? If yes, **CRITICAL**. The `staticwebapp.config.json` route gate must be present in the deploy artifact; an anonymous `curl` against any URL of the deployed environment must redirect/401 before content. Verify, do not assume.
- **D22 time-bounded corollary (active until Epic 3.4 supersedes the corollary bullet in `CLAUDE.md` in place):** is anything beyond the trivial skeleton (the "SLAYList — it works" page + a trivial `/api/health` endpoint) shipping behind the Epic-2-era gate? If yes, **CRITICAL** — the gate trusts any Microsoft account, not just family. When Epic 3.4's `/close-sprint` lands, this check is **superseded in place** — rewritten to a one-line historical pointer ("Corollary resolved by Epic 3.4 — see the historical note in `CLAUDE.md`"), NEVER silently deleted. Same supersession pattern used in `docs/DECISIONS.md`.
- Every new endpoint authenticated AND role-checked server-side (not just hidden in UI).
- Upload validation server-side; size cap enforced; no path traversal from filenames.
- Finished audio not silently public; access scoped.
- Least-privilege access for container/queue/storage. Base images reasonably current.
- "Shared" never means public.
- **No PII in logs (D32) — every sprint that adds log statements or telemetry.** Scan new log statements for: any field named or containing `ownerDisplayName`, `preferred_username`, `email`, `displayName`, or `title` (song titles contain kids' names). Any of these flowing to App Insights = **CRITICAL**. Acceptable substitutes: `ownerOid`, `songId`. For transcoder sprints, verify ffmpeg stderr is captured via the D32 mitigation (songId-based local filenames OR substitution before emit) — not raw stderr direct to App Insights.
- **`raw-uploads` deletion check (D28) — every sprint that touches the storage account, lifecycle rules, or any "cleanup" job.** Any code, lifecycle rule, or scheduled task that *deletes* from `raw-uploads` = **CRITICAL**. Tier-transition lifecycle rules (Hot→Cool→Archive) are fine; deletion is forbidden. The kids' originals are canonical archive.
- **Personal-machine local-path leak (every sprint that adds or edits committed content — files OR commit messages).** Scan for:
  - **Windows drive-letter paths:** `[A-Za-z]:\` or `[A-Za-z]:/` followed by a user/project-specific directory name (e.g., `C:\Users\<name>\...`, `C:\dev\<project>\...`, `D:\<anything>\<project>\...`).
  - **Unix user-home paths:** `/home/<name>/...`, `/Users/<name>/...`, `~/<project>/...`.
  - **Commit messages** count — `git log` is permanent on a public repo. Scan with: `git log -p develop..HEAD | grep -iE '[A-Za-z]:[\\/]|/home/[^/]+/|/Users/[^/]+/' | head -20` and inspect each hit.
  
  Generic placeholders (`<your-project-path>`, `/path/to/your/repo`, "your project directory") are fine. A real path that identifies a specific machine, user, or local directory choice = **MODERATE** finding (or **CRITICAL** if the path reveals family/organizational info or has been on the public repo for an extended period without notice). See the "Personal-machine local paths" rule in `docs/DEVELOPER_GUIDE.md` "Public-repo hygiene".
- **Individual-contributor-name leak (every sprint that adds or edits committed content — files OR commit messages OR PR/issue bodies).** The repo's voice is contributor-agnostic on every public-readable surface — proper nouns identifying individual people, specific tools, or vendor orgs don't belong in committed prose; role names ("the owner", "the agent", "a reviewer", "an uploader", "a listener", "a kid") or passive voice do. See the "Speak in roles, not in individual names" rule in `docs/DEVELOPER_GUIDE.md` "Public-repo hygiene" for the full principle + carve-out list.

  **Scan three surfaces. Tune the proper-noun regex to whatever individual names the current contributor base might leak (human first names + tool/vendor names known to be in play):**
  - **Files staged in the diff** — `git diff develop..HEAD | grep -E '^\+' | grep -E '<your-name-list-regex>'`
  - **Commit messages on the branch** — `git log develop..HEAD --format=%B | grep -E '<your-name-list-regex>'`
  - **PR description body when the PR is open** — `gh pr view <N> --json body --jq .body | grep -E '<your-name-list-regex>'`

  **Always exclude the carve-out paths** (see DEVELOPER_GUIDE.md for the full list — these are literal tool-config / filesystem references, not prose):
  ```
  ... | grep -v 'CLAUDE\.md' | grep -v '\.claude/' | grep -v '^Signed-off-by:' | grep -v '^Author:' | grep -v 'Copyright (c)'
  ```

  A hit on any surface = **MODERATE** finding; **CRITICAL** if it's a `Co-Authored-By: <person-or-tool>` trailer (those become contributor attributions on GitHub's Contributors view — the load-bearing reason this check exists).

### 5. Support
- Is it usable by a non-technical family member / kid on a phone?
- Clear states and messages for logged-out, wrong-role, processing, failed.
- Docs/README followable by someone who isn't the author.

## Output to the human

1. A table of all findings: reviewer · severity · finding · suggested fix.
2. **Recommendation:**
   - If ANY finding is CRITICAL → recommendation is **DO NOT PROCEED until criticals are fixed.** List them first.
   - Otherwise → recommend which moderates/lows to fix now vs. backlog, with reasoning.
3. Ask the human what to fix. The human may override (e.g. "fix all now", or "backlog that critical with eyes open"). Respect the override but record it.

## After the human decides
- Apply the agreed fixes.
- Anything deferred goes into `docs/BACKLOG.md` under "Emergent", with severity noted.
