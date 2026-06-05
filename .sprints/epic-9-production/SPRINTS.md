# Epic 9 — Production Environment & Promotion

**Goal:** Stand up prod (separate from dev) and a clean promotion flow. Deliberately late — no point maintaining two environments before there's something worth promoting.

**Exit criterion:** a clean dev→prod flow exists and the kids use the prod URL. **The first prod deploy is already gated** (D22) and already authorized to family members only (Epic 3's custom Entra app + roles, not the pre-configured AAD provider) — there is no prod-side Path-A′ window.

**Guardrail (D7):** prod data stores physically separate (separate storage account, queue, Container App). SWA prod env vs staging. Human gates main→prod (D14).

**Guardrail (D22, every-environment invariant):** prod must satisfy "no environment publicly reachable without authentication, from first deploy." Because Epic 3 is a prerequisite for this epic, prod inherits the full custom Entra app registration + role-based authz from the very first `main`-deploy — no any-Microsoft-account gap ever exists in prod.

---

## Sprint 9.1 — Create prod resources + decide SWA tier  **[Human, guided]**
- As the owner, I want prod copies of the resources, isolated from dev.
- As the owner, I want the **SWA tier decision (D26) made here, deliberately** — not discovered later. Two valid choices: (a) **Free tier**, accepting the default `*.<region>.azurestaticapps.net` URL — zero cost, matches dev — or (b) **Standard tier (~$9/mo)** to unlock a custom domain (`*.<your-domain>`) for a more memorable family-facing URL. This is a "documented known future fork" per D26; the choice is recorded in `docs/VERSIONS.md` + `docs/DECISIONS.md` as a new entry superseding D26's "Free for both" stance if Standard is chosen.
Acceptance: prod resource group, storage account (blobs+table, soft-delete+versioning+retention), Container App with Managed Identity + RBAC (per D25), Event Grid+queue, budget alert (a sensible prod number — likely higher than dev's $15/mo because real traffic exists; pick deliberately), prod Application Insights instance (D24); SWA production environment **with the tier choice from above documented**. If Standard is chosen, the custom domain is configured and DNS pointed in this sprint (or split into 9.1a/9.1b — let `/start-sprint` planning decide).

**Note on the prod budget (carried forward from Sprint 1.1):** Sprint 1.1 created a *dev* RG-scoped budget at $5/$12/$15 on `rg-music-slaylist-dev-use2` and explicitly deferred the matching prod budget to this sprint. **Mirror the same three-rung pattern** (early warning / 80% / 100%), scoped to `rg-music-slaylist-prod-use2`, with notification to the owner email. **Recalibrate the dollar amounts** against prod's actual expected baseline — prod has real traffic, real storage growth (D28 originals kept indefinitely), real Container App execution time, and (if SWA Standard is chosen) ~$9/mo of SWA cost. Pick deliberately; don't copy $15 verbatim. Capture the chosen numbers + the reasoning in `infra/prod-resources.md` (gitignored) and reference in this sprint's close-out.

**Note on the prod deploy identity (D41 — prerequisite for Sprint 9.2's `main`→prod workflow):** prod's ARM resources above come from the Bicep (`env=prod`, D39), but the prod **deploy identity** — the `main`-branch federated credential + prod-RG Contributor + prod GitHub variables/secrets — is NOT Bicep; it's provisioned by **re-running `scripts/bootstrap-deploy-identity.*` with prod parameters** (D41), and must exist before 9.2's workflow can deploy. **One-vs-two: decided at Sprint 2.1 — SEPARATE app per environment (D7).** The bootstrap script defaults the app name to `slaylist-github-deploy-<env>`, so running it with `-Env prod -Branch main` creates a *distinct* `slaylist-github-deploy-prod` app scoped to the prod RG only. A `develop`-branch run holds zero prod RBAC and can never touch prod (and vice versa) — stronger blast-radius containment, which matters most on a public repo where `develop` sees frequent, less-scrutinized merges. No decision left to make here; just run the prod bootstrap. Attest the prod variables/secrets (`gh variable list`, `gh secret list`) with the SWA prod token absent from secrets (D37), same as Sprint 2.1.

## Sprint 9.2 — Extend pipeline: main → prod  **[Agent]**
- As the owner, I want `main` to deploy to prod while `develop` keeps deploying to dev.
Acceptance: workflow deploys prod on `main`; prod secrets/config separate from dev; human-gated merge enforced; **the prod-bound `staticwebapp.config.json` already contains the custom-Entra-provider auth gate (D22) — the first prod deploy is never anonymous-reachable, never gated by the pre-configured AAD provider.**

**Consider (preview-slot prod validation):** the Sprint 2.2 dev workflow deploys to the SWA's `production` slot directly. For prod, consider deploying first to a SWA **named/preview environment** (a separate slot/URL), validating there, then promoting to the `production` slot — a safer "validate before the main URL changes" flow. Caveats to weigh at planning: SWA **named environments require Standard tier** (interacts with the D26 SWA-tier decision made in 9.1 — Free tier only has `production` + auto PR previews), and SWA has **no atomic slot-swap** like App Service, so "promote" means redeploying the validated build to `production`, not a swap. Worth it once prod is real and a bad deploy would disrupt the kids' live site.

## Sprint 9.3 — First promotion + prod smoke test  **[Both]**
- As the owner, I want to promote dev→prod once and confirm the full loop in prod.
Acceptance: first PR develop→main merged by human; prod deploy succeeds; upload→ready→play works in prod; budget alert live.

---
### Reviewer focus (/wrap-sprint)
- Infosec (lead): prod secrets isolated from dev; prod access least-privilege; no dev credentials usable against prod.
- DevOps: rollback story understood; prod deploy observable; environments truly separate.
- Solution architect: D7 honored end to end (no shared data store slipped in).
- Sr dev: config cleanly parameterized dev vs prod (no hardcoded env).
- Support: prod URL/login documented for the family.
