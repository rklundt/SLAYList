---
description: Sync docs, prepare the PR to develop, and run a Claude-Code/human consult on any merge conflict. The human performs the merge.
---

# /close-sprint

Close out the sprint: make the record true, then prepare (not perform) the merge.

## Step 1 — Doc sync and contradiction sweep (do this BEFORE the PR)

Compare what was actually built against the docs and flag misalignment:

- **`CLAUDE.md`** — did this sprint change a guardrail, supersede one in place (e.g., Epic 3.4's supersession of the D22 corollary), or invalidate one? Propose the edit. **The supersede-in-place pattern (active rule → historical note, never deleted) applies here: NEVER silently remove a guardrail bullet — rewrite it to a historical note pointing at the sprint that retired it.** Same pattern this project uses in `docs/DECISIONS.md` (D12 → D19). If the sprint's acceptance criteria explicitly call for a CLAUDE.md change (e.g., "supersede the D22 corollary in place"), this is the step where it happens.
- **`docs/ARCHITECTURE.md`** — did this sprint change how anything actually works? Propose the edit.
- **`docs/DECISIONS.md`** — did this sprint make or change an architectural decision? If a decision was superseded, propose a NEW entry that supersedes the old one (don't silently rewrite history). If the sprint CONTRADICTS a standing decision and that wasn't explicitly approved, STOP and raise it with the human — this is exactly the downstream-impact check the docs exist for.
- **`docs/VERSIONS.md`** — pin any new versions / milestones; record any dated verification (e.g., re-verified SWA runtime support).
- **`docs/BACKLOG.md`** — resolve any "open questions" this sprint answered (e.g. input allowlist, output format, retention window); move emergent items in.
- **`.claude/commands/wrap-sprint.md`** — if a `/wrap-sprint` check was time-bounded to this sprint (e.g., the D22 corollary InfoSec check retired by Epic 3.4), supersede the check in place — rewrite to a one-line historical pointer, never delete.
- **`.sprints/INDEX.md`** — update this sprint's status (✅), and re-check whether anything built changes a LATER sprint's assumptions; note it on that sprint if so. **If this is the last sprint of an epic**, also add (or update) an explicit `**Status: ✅ DONE.**` line under the epic header, with the epic's exit criterion baked into the wording so the status doubles as a record of what "done" actually meant. This convention was established by Sprint 0.4's close — every epic close from here on uses it so future readers don't have to infer epic-completion by visually checking that every sub-sprint happens to be ✅.

Present the proposed doc edits to the human. Apply on confirmation. **Docs must be true before the PR — a stale architecture doc is worse than none.**

## Step 2 — Prepare the PR to `develop`

- Ensure work is on the sprint branch `sprint/<epic>-<sprint>-<slug>`.
- **Verify every commit on this branch is signed off (D16) BEFORE pushing.** Per `CONTRIBUTING.md`, PRs without sign-off do not merge — catching this here avoids a forced amend/rebase pass after pushing. Run a check that lists any commit lacking the `Signed-off-by:` trailer in its message body. One reasonable form:

  ```bash
  git log develop..HEAD --pretty=format:'%H %s' | while read sha rest; do
    git log -1 --format=%B "$sha" | grep -q '^Signed-off-by:' || echo "MISSING SIGN-OFF: $sha $rest"
  done
  ```

  (`%G?` shows GPG signature status, not DCO sign-off — the trailer-in-message-body check above is the right one for D16.)

  **If any commit lacks sign-off, REFUSE to push.** Present the missing commits to the human and propose `git rebase --signoff develop` (non-interactive; adds `Signed-off-by` to every commit on the branch from `develop` forward). The human confirms before any history-rewriting command runs — rebasing rewrites history and is the human's call to make. Then re-run the check.

- Commit any final fixes with a clear message (and `-s`); push.
- Open a PR into `develop` with a full description: what was built, which user stories/acceptance are met, which `/wrap-sprint` findings were fixed vs. deferred (with the human's overrides recorded), and which docs changed.

## Step 3 — Merge conflicts: Claude-Code/human consult

If the PR has conflicts:
- Do **NOT** auto-resolve.
- For each conflict, explain what each side changed and WHY (reference the sprint/decision if relevant), and propose a resolution with your reasoning.
- Present these to the human as a consult. The human confirms or corrects each resolution before anything is applied.

## Step 4 — The human merges

- The human performs the actual merge into `develop` (the merge is the moment of consequence).
- Merging `develop` kicks the pipeline → deploys to the dev Azure environment.
- Tell the human the dev URL / where to QA play-test, and what to specifically verify for this sprint's acceptance criteria.

## Step 5 — Prod promotion (only when the human chooses)

- When the human is satisfied with dev QA, prepare a PR from `develop` → `main`.
- Same consult rule on conflicts. **The human merges to `main`** → deploys to prod.
- Never merge to `main` autonomously.

## Hard rules
- Docs are made true before the PR, not after.
- Contradicting a standing decision without explicit approval is a STOP-and-ask, not a proceed.
- Claude Code prepares merges and consults on conflicts; the human merges.
