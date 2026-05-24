---
description: Re-establish context for a sprint, audit existing code, and plan the work before breaking ground.
argument-hint: <epic>/<sprint>  e.g. epic-0-foundations/0.1
---

# /start-sprint

You are starting work on a sprint. Do NOT write feature code until the human approves your plan.

## Steps

1. **Reload context, in this order:**
   - `CLAUDE.md` (rules and guardrails)
   - `docs/ARCHITECTURE.md` (the settled design)
   - `docs/DECISIONS.md` (why things are the way they are — note any decision that touches this sprint)
   - `docs/DEVELOPER_GUIDE.md` (the public-repo hygiene rules, file-header convention, Node version policy, library-id and PII rules — these apply to *every* sprint, not just doc sprints)
   - `docs/VERSIONS.md` (pinned versions and the dated verification trail; any sprint that touches Node/deps/runtime needs this)
   - `.sprints/INDEX.md` (where this sprint sits and what depends on it)
   - The target sprint file: `.sprints/$ARGUMENTS` (or the epic's `SPRINTS.md`)

2. **Audit reality.** Inspect the actual codebase. What from this sprint (or its prerequisites) already exists? Does the current code already contradict any doc? Note gaps between docs and reality — do not silently accept either; flag mismatches.

3. **Check dependencies.** Confirm the prerequisite sprints (per INDEX dependency shape) are actually done. If a prerequisite is incomplete, say so and stop — don't build on sand.

4. **Produce a plan** for the human containing:
   - The sprint's user stories and acceptance criteria, restated.
   - The concrete tasks you intend to do, in order, each tagged [Claude Code] or [Human] (some sprints need the human to do Azure portal work first — surface that up front).
   - Any DECISIONS that constrain this work, and any place the sprint tempts a rejected alternative.
   - **If this sprint deploys anything:** explicitly call out that the deploy artifact MUST include the D22 auth gate config (the `staticwebapp.config.json` route gate, or its environment-appropriate equivalent for any non-SWA deploy in a later epic). No deploy ever ships without the gate already in the artifact.
   - **If this sprint creates source files:** explicitly call out that every new `.ts`/`.tsx`/`.js`/`.css`/`.sh`/`.ps1`/`.yml`/`Dockerfile` gets the two-line SPDX header (D15) at creation time, not retrofitted at `/wrap-sprint`.
   - Any open question that needs a human answer before you start (e.g. the input allowlist in Epic 5, output format in Epic 6).
   - What "done" will look like and how you'll verify it.

5. **Stop and wait for approval.** Only break ground after the human confirms the plan.

## Hard rules
- Never make an architectural decision silently. If the sprint pushes against a DECISIONS entry, raise it.
- If the sprint requires a human Azure step, write the step-by-step guide (into `docs/guides/`) as part of the plan, so the human can act.
- **Every new source file carries the two-line SPDX header (D15)** at creation. `Copyright (c) <year> Ray Klundt` + `SPDX-License-Identifier: AGPL-3.0-or-later` in the language's comment syntax. Pure-data files (`package.json`, lockfiles, `.gitignore`, etc.) and markdown are exempt. Plan to apply this as you write, not as a cleanup pass.
- **Every commit on the sprint branch is signed off (D16)** via `git commit -s`. Per `CONTRIBUTING.md`, PRs without sign-off do not merge — make sign-off your default from the first commit of the sprint, not something you fix at `/close-sprint`.
- **Every deployed environment is auth-gated from its first deploy (D22).** Any sprint that deploys must ship the gate config *in the deploy artifact*. The gate is never absent; it only evolves (Epic 3 strengthens Epic 2's pre-configured AAD redirect to a custom Entra provider; later epics never weaken it). If a deploy step in your plan doesn't have a gate-config-included acceptance, the plan is wrong — STOP and surface it.
- **Public-repo hygiene applies to everything you write.** No secrets, no real Azure resource names, no PII (including real `ownerDisplayName` values), no family-identifying detail in committed files. The rules live in `docs/DEVELOPER_GUIDE.md` "Public-repo hygiene" — re-read that section if anything you're about to write feels close to the line.
