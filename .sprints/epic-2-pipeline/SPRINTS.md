# Epic 2 — Deployment Pipeline (dev, on the skeleton)

**Goal:** Connect Epic 0's skeleton to Epic 1's dev resources via GitHub Actions, while the app is still trivial. Prove the plumbing on something with no features.

**Exit criterion:** pushing to `develop` auto-deploys the skeleton to dev Azure; **the deployed URL is reachable only after authentication** (D22) — anonymous visitors are redirected to sign in before seeing anything; once signed in, they see the trivial "SLAYList — it works" page.

**Hard invariant for this epic (D22):** *No deployed environment is ever reachable on the public internet without authentication in front of it — from the very first deploy.* The first deploy of this epic is the first time the project is on the internet; it must already be gated. Path A′ (verified against `learn.microsoft.com/azure/static-web-apps/configuration`, 2026-05-24): ship a `staticwebapp.config.json` that requires `authenticated` on `/*` and redirects 401 → `/.auth/login/aad` (SWA's pre-configured Microsoft provider). No Entra portal work yet — that's Epic 3.

**Time-bounded rule (D22 corollary, lives until Epic 3 closes):** The Epic-2-era gate is authentication-only and trusts any Microsoft account. So this epic ships **only** the trivial skeleton (the "SLAYList — it works" page from 0.3 + a trivial `/api/health` endpoint) behind it. No real content, no real records, no upload, no song data — those wait for Epic 3's role-based authz.

---

## Sprint 2.1 — Deploy auth via OIDC federation (D30 + D37) + GitHub Actions secrets for non-deploy values  **[Both]**
- As the owner, I want Azure deploy auth via **OIDC federation, NOT a long-lived service-principal client secret** (D30) — for a public repo, a stored deploy secret is exactly the high-blast-radius credential to avoid.
- As the owner, I want the SWA deploy itself to also go through OIDC (D37) — `az staticwebapp deploy` under an OIDC-auth'd `az login`, NOT `Azure/static-web-apps-deploy@v1` + the SWA deployment token in GitHub Secrets. The SWA deployment token captured at 1.2 stays in gitignored local notes as a documented break-glass fallback only.
- As the owner, I want the small set of non-deploy app-settings values (storage connection string, App Insights connection string) stored as GitHub Actions secrets so CI can wire them into SWA app settings without putting them in the repo.

Acceptance:
- A dedicated Entra app registration exists for deploy, with **federated credentials** keyed to this repository and branches (`repo:<owner>/<repo>:ref:refs/heads/develop` for dev; `repo:<owner>/<repo>:ref:refs/heads/main` for prod added in Epic 9). **No client secret is created or stored.**
- The federated identity has Contributor RBAC on the dev resource group only (NOT subscription-scope). Prod RG assignment is added in Epic 9.
- GitHub Actions workflow uses `azure/login@v2` with `client-id` + `tenant-id` + `subscription-id` (all repo variables, none secret in the OIDC sense — the auth itself is via the OIDC JWT exchange).
- Required GitHub Actions secrets present: **storage account connection string** (from 1.3), **App Insights connection string** (from 1.1). Each documented in `infra/dev-resources.md` (gitignored): which secret feeds which app setting. The **SWA deployment token is explicitly NOT stored in GitHub Secrets** per D37 — it lives only in gitignored `infra/dev-resources.md` as a break-glass fallback.
- Nothing sensitive in the repo; `gh secret list` output recorded in the sprint close-out (must show the storage + App Insights secrets only — no SWA-deploy-token secret).

## Sprint 2.2 — Actions workflow (build + deploy to dev SWA) + auth gate + CI tests (soft mode)  **[Claude Code]**
- As a developer, I want a workflow that builds frontend + API and deploys to the dev Static Web App on push to `develop`.
- As the owner, I want the deployed dev URL to require authentication from the very first deploy (D22) so we never have a "ship open, secure later" window.
- As a developer, I want **CI to run Vitest on every push** (D23) so test red/green is visible from now on — but in **soft mode** until Epic 4.1 hardens it (failures show but do NOT block the merge during scaffolding-phase epics).
Acceptance:
  - Workflow file in `/.github/workflows`; triggers on `develop`; builds both; deploys to dev SWA.
  - `staticwebapp.config.json` ships with the deploy and contains the D22 Path-A′ auth gate: `routes: [{ route: "/*", allowedRoles: ["authenticated"] }]` + `responseOverrides: { "401": { statusCode: 302, redirect: "/.auth/login/aad" } }`.
  - Same config file also sets `platform.apiRuntime = "node:22"` (D18).
  - **A test job runs `pnpm test` (Vitest) across workspaces on every push (D23 + D34). In soft mode: the job runs and reports results, but does not block the merge. Add an explicit comment in the workflow file:** `# Soft-mode: test failures do NOT block merge until Sprint 4.1 hardens this (D23).` This comment is the breadcrumb 4.1 looks for.
  - **pnpm + SWA build verified working end-to-end (D34 — load-bearing, not a formality).** SWA's Oryx build auto-detects `package-lock.json` and runs `npm ci` for free; pnpm requires explicit config that we accepted as the cost of D34. Pick one path and verify it works **on the actual deployed dev SWA** (not just locally): (a) set `BUILD_FLAGS` to install pnpm before Oryx's npm step, OR (b) install pnpm in the GitHub Actions workflow (`pnpm/action-setup@v4` with `version` matching `package.json`'s `packageManager` field), use `pnpm install --frozen-lockfile`, and bypass Oryx's npm step entirely by setting `app_build_command`/`api_build_command` to pnpm-based commands. If the verification fails or is more painful than expected, escalate per D34's "documented reconsider-point" rather than working around silently. Record the chosen path as a D34 implementation-note addition in `docs/DECISIONS.md` at this sprint's `/close-sprint`.
  - **OIDC-authenticated `az staticwebapp deploy` path verified end-to-end on SWA Free tier (D37 — load-bearing platform claim, not a formality).** Workflow uses `azure/login@v2` with OIDC (D30) then `az staticwebapp deploy` (or `swa deploy` with explicit OIDC token if `az staticwebapp deploy` isn't yet available in the chosen Azure CLI version on the runner). **No `Azure/static-web-apps-deploy@v1` + deployment-token-from-secrets pattern is used** — that's the D37-rejected (A) path. Acceptance is **the deploy succeeds AND the artifact actually contains frontend `dist/` + api `dist/` + `staticwebapp.config.json` at the expected paths** (not just "the workflow step exits 0"). If the OIDC path fails for a platform reason (e.g., the SWA Free-tier deploy endpoint doesn't accept OIDC at the time of verification, or the `az staticwebapp` subcommand isn't GA), STOP and per D37's reconsider-trigger discipline either (i) fall back to the break-glass token *for this one verification* and document the platform gap as a new D-entry superseding D37 in place, OR (ii) flag to the human for an alternative path. Record the verification outcome as a one-line D37 implementation-note addition in `docs/DECISIONS.md` at this sprint's `/close-sprint` ("OIDC deploy path verified clean on YYYY-MM-DD" or "verified-with-caveat:…"). Same verify-don't-assume discipline as D18 / D27 / D34 / D36.

  - **pnpm + SWA build verified end-to-end on the actual dev SWA (D34 — load-bearing, separate concern from D37).** D34 owns the build-tooling question (Oryx + npm vs pnpm install in CI); D37 owns the deploy-auth question (OIDC vs token). Both must verify. Pick a path for the pnpm build per D34's documented options — (a) BUILD_FLAGS to install pnpm before Oryx's npm step, OR (b) install pnpm via `pnpm/action-setup@v4` in the workflow and bypass Oryx's npm step entirely — and confirm the deploy artifact is correctly assembled. Record chosen path as a D34 implementation-note addition at `/close-sprint`.
  - **Application Insights connection string (D24) wired into the deploy** via SWA app settings (from the GitHub Actions secret captured in Epic 1.1) — the deployed API can emit telemetry from its very first request, even if there's nothing meaningful yet to emit.
  - **Storage account connection string (D25) wired into SWA app settings** (from the GitHub Actions secret captured in Epic 1.3) — even though the Epic 2 skeleton doesn't use storage yet, the connection is in place so Epic 4's first API endpoint that *does* use storage doesn't need separate plumbing work.

## Sprint 2.3 — Run it and fix first-deploy errors + verify the gate  **[Both]**
- As the owner, I want the first real deploy to succeed AND the gate to actually deny anonymous access so the pipeline AND the invariant are both proven.
Acceptance:
  - A push to `develop` results in the gated skeleton live at the dev SWA URL.
  - **Verification:** an anonymous browser session hitting the URL is redirected to `/.auth/login/aad` (not served the page). After Microsoft sign-in, the "SLAYList — it works" page renders. `curl` to `/api/health` without a session returns 401, with a session returns 200. Record these checks in the sprint close-out.
  - First-time auth/config errors resolved and noted.

---
### Reviewer focus (/wrap-sprint)
- **Infosec (lead this epic):** the D22 invariant holds — anonymous browser cannot reach any URL of the deployed app; `staticwebapp.config.json` route gate present and correct; `/api/health` returns 401 to unauthenticated callers. Secrets only in GitHub secrets; workflow doesn't echo them; least-privilege deploy identity. **Verify D37 explicitly:** `gh secret list` shows storage + App Insights connection strings only — no SWA-deploy-token secret. The workflow does NOT use `Azure/static-web-apps-deploy@v1` with a `azure_static_web_apps_api_token` input; it uses OIDC-authenticated `az staticwebapp deploy` instead. **Critical finding** if the deploy is anonymously reachable, OR if anything beyond the trivial skeleton ships behind the Epic-2-era gate (per D22's time-bounded corollary), OR if the SWA deployment token ends up in any GitHub Actions secret (per D37).
- DevOps: workflow is idempotent; failure is visible; only `develop` deploys to dev (no accidental prod path yet).
- Solution architect: pipeline matches the branch→environment model (D7); the `staticwebapp.config.json` gate is the artifact that evolves in Epic 3 (D22) — no parallel auth mechanism introduced.
- Sr dev: build is reproducible from clean checkout.
- Support: a failed deploy gives a legible signal; a logged-out visitor sees the Microsoft sign-in page, not a blank failure.
