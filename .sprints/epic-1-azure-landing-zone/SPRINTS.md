# Epic 1 — Azure Landing Zone (dev resources)

**Goal:** Create the dev-side Azure resources, by hand the first time so the owner understands them. A step-by-step guide is written before each human task.

**Exit criterion:** dev resources exist in the portal. Nothing wired together yet.

**Reminder (DECISIONS D7):** these are the DEV copies, deliberately separate from prod. Data stores are physically separate per environment.

---

## Sprint 1.1 — Resource group, naming, budget alert, Application Insights  **[Human, guided]**
- As the owner, I want a dev resource group and a documented naming convention so resources are findable and consistently named.
- As the owner, I want a **budget alert at $15/month** so an unexpected cost emails me. (Free insurance — generous enough that a normal month never false-alarms, low enough that anything genuinely runaway trips it.)
- As the owner, I want an **Application Insights instance for dev (D24)** so failure observability exists from day one — before any of Epic 6/7's transcode/queue logic lands, so it can never be debugged blind. App Insights is the single failure sink fed by SWA managed functions, the Container App transcoder, and Storage diagnostics.
Acceptance: dev resource group exists; naming convention in `infra/` notes (canonical location per Sprint 0.2's repo layout — `infra/`, NOT `docs/infra/`); budget + alert configured at **$15/month**; **dev Application Insights instance exists and its connection string / instrumentation key is captured for Epic 2's deploy config (stored as a GitHub Actions secret, not in repo)**.

## Sprint 1.2 — Dev Static Web App  **[Human, guided]**
- As the owner, I want a dev Static Web App **on the Free tier (D26)** so the skeleton has a deploy target with no per-environment cost.
Acceptance: dev SWA exists on **Free tier**; deployment token captured for Epic 2 (stored in gitignored `infra/dev-resources.md` as a **D37** break-glass fallback only; **NOT** in GitHub Secrets, **NOT** in repo — Sprint 2.2 deploys via OIDC-authenticated `az staticwebapp deploy` per D37, not via the token). Note for future-you: Standard tier unlocks custom domains, IP allow-lists, and bring-your-own functions; per D26 we are deliberately on Free for now, and the prod-custom-domain decision is Epic 9's.

## Sprint 1.3 — Dev storage account (blobs + table)  **[Human, guided]**
- As the owner, I want a dev storage account holding three blob containers (`raw-uploads`, `finished`, `table-backups`) and the metadata table.
- As the owner, I want soft-delete + versioning on the audio containers, with a chosen hard-delete retention window.
- As the owner, I want the **storage auth posture per D25** ready to use from Epic 2 forward: the SWA managed-functions API will read this account via a connection string (Managed Identity is unavailable on managed functions — platform-forced); the Container App transcoder will read it via Managed Identity in Epic 6.
- As the owner, I want **`raw-uploads` configured as the canonical archive per D28** — soft-delete + versioning on, AND no deletion-class lifecycle rule ever applied to this container. The kids' originals live here forever.
- As the owner, I want a **`table-backups` container provisioned (D33)** so Epic 4.4's nightly Table export has a destination already in place; lifecycle rule on `table-backups` may auto-prune backups older than 30 days (this is a backup-pruning rule and is fine — does NOT contradict D28's no-deletion-on-`raw-uploads` rule).

Acceptance:
- Storage account exists; `raw-uploads`, `finished`, and `table-backups` containers created; Song table created.
- Soft-delete + versioning enabled on `raw-uploads` and `finished`; retention window decided and recorded in BACKLOG resolution + VERSIONS.
- **`raw-uploads` has NO deletion-class lifecycle rule (D28)** — explicitly verified by listing lifecycle rules in the portal after configuration. Tier-transition rules (Hot → Cool → Archive) are fine if added later.
- **`table-backups` container exists** (empty for now; populated by Epic 4.4).
- **The storage account connection string is captured for Epic 2's SWA app settings + GitHub Actions secrets** (never in repo per D25 + the no-secrets-in-code guardrail in `CLAUDE.md` — this is now a load-bearing secret, not academic).

## Sprint 1.4 — Dev Container App environment  **[Human, guided]**
- As the owner, I want a dev Container App environment so the transcoder has somewhere to run.
- As the owner, I want the Container App to use **Managed Identity (D25)** for its storage access — granted Storage Blob Data Contributor + Storage Table Data Contributor on the dev storage account from 1.3. This is the cleaner half of the split auth posture D25 documents.
Acceptance: Container App environment exists (the app image comes in Epic 6); scale-to-zero capability confirmed; **Managed Identity enabled on the environment, with the two storage RBAC role assignments recorded against the dev storage account (no connection string used by the transcoder, ever)**.

## Sprint 1.5 — Dev Event Grid + queue  **[Human, guided]**
- As the owner, I want the dev Event Grid topic/subscription and the dev queue so blob events can later route to the transcoder.
Acceptance: queue created (Storage Queue per DECISIONS D6); Event Grid ready to subscribe to blob-created events (wired in Epic 7).

## Sprint 1.6 — IaC capture (Bicep) for the dev landing zone  **[Both]**

*Added after Sprint 1.5's close-sprint review, in response to the operational question: "should we capture this as ARM/Bicep/Terraform so we can re-publish dev and derive prod?" Format chosen: **Bicep** — Microsoft's native DSL that compiles to ARM; clean syntax; first-class `az` CLI tooling; no state-file management overhead (Terraform's posture is over-engineered for our scale; we're Azure-only by design per D4/D24/D25/D26/D34). Capture timing chosen: now, before Epic 2 starts building infra-touching deploy pipelines, so the deploy pipeline can be designed with IaC as the source of truth from day one.*

- As the owner, I want the Epic 1 dev resources captured as Bicep so dev can be rebuilt from code (disaster recovery), prod (Sprint 9.1) is a parameter-substitution deploy rather than another 5-sprint portal walkthrough, and future infra changes go through reviewable PRs instead of portal clicks.

- As the owner, I want the Bicep templates to **not** carry secrets (connection strings, MI Principal IDs are deployment **outputs** from Azure, never inputs to the template) so D17 public-repo hygiene holds naturally and the existing gitignored `infra/dev-resources.md` discipline still applies to runtime credentials.

- As the owner, I want the Bicep verified by **deploy-to-throwaway-RG + `az resource list` comparison** (same verify-don't-assume discipline as Sprint 1.1's AI ingestion / Sprint 1.3's storage diagnostics) so we know the template actually reconstructs the current dev state, not just "compiles clean."

Acceptance:
- Bicep modules under `infra/bicep/` (env-neutral, per-resource-type split — `main.bicep`, `naming.bicep`, `storage.bicep`, `containerapp.bicep`, `eventgrid.bicep`, `observability.bicep`, `swa.bicep`) covering every Epic 1 dev resource: RG (or scoped-to-existing-RG), LAW, App Insights (workspace-based), $15/mo RG-scoped budget alert at $5/$12/$15 rungs, SWA on Free tier (Deployment source = Other; no auto-GitHub-workflow per D22 safeguard), Storage account with 3 containers (`raw-uploads`, `finished`, `table-backups`) + `Songs` table + 2 queues (`transcode-jobs`, `transcode-jobs-poison`) + 3 diagnostic settings (blob/table/queue → LAW) + 30d soft-delete + versioning, Container App Environment (Consumption profile, env-linked to LAW), Container App (placeholder image, Ingress Disabled, scale 0-1, system-assigned MI) + 2 storage RBAC role assignments (`Storage Blob Data Contributor` + `Storage Table Data Contributor`, scope = storage account), Event Grid system topic with system-assigned MI + 1 diagnostic setting (DeliveryFailures + AllMetrics → LAW — note: system topics support only `DeliveryFailures`, not the custom-topic `PublishFailures`/`DataPlaneRequests` categories, verified at Sprint 1.6).
- Parameters: `env` (`dev`/`prod`), `region` (`use2`), `workload` (`music`), `app` (`slaylist`) — so Sprint 9.1 prod creation is `az deployment group create -p env=prod -p region=use2 -g rg-music-slaylist-prod-use2 -f main.bicep` and nothing else changes.
- Outputs: **non-sensitive values only** — Resource IDs, MI Principal IDs, default hostnames, and the (non-secret) App Insights connection string — exposed as Bicep `output` blocks. *(Superseded in place at Sprint 1.6 wrap: the original wording listed the storage account connection string + SWA deployment token among the outputs. On implementation this was judged to contradict D17/D32 — a Bicep `output` flows into ARM deployment history and CI/`what-if` logs, which on a public-repo-tracked template is exactly the secret-exposure surface D30/D37 exist to shrink. **Secrets are NOT emitted as outputs;** they are fetched post-deploy via `az storage account keys list` / `az staticwebapp secrets list` and captured in the gitignored `infra/dev-resources.md`. Recorded as the D39 "secrets posture." The one cost — an extra `az` call after deploy — is trivial against the blast radius. The original intent ("without those values living in committed source") is preserved and strengthened: now they don't live in deployment history either.)*
- **`bicep build` clean** on all modules (compiles to ARM without warnings).
- **Validated end-to-end** by deploying to a throwaway RG (`rg-music-slaylist-iac-validate-use2` — or similar; explicitly NOT the live `rg-music-slaylist-dev-use2`) and confirming `az resource list -g <throwaway-rg>` shows the same resource shape as the existing dev RG. Throwaway RG deleted after verification; attestation captured in the gitignored `infra/dev-resources.md`.
- **Naming convention `managed-by` tag retention:** Bicep declares `managed-by=bicep` for all resources it provisions (per `infra/naming-convention.md`'s contemplated alternative). The **existing live `rg-music-slaylist-dev-use2` resources retain `managed-by=manual`** at Sprint 1.6 — no migration of the existing dev to be IaC-managed in 1.6 scope; that migration is a separate sprint if/when wanted (the option is open; the Bicep templates work either way against a fresh RG vs. an existing one).
- **Sprint 7.1's Event Grid subscription added to Bicep at Sprint 7.1** (not at 1.6) — keeps IaC in sync with the actual wiring sequence; 1.6 captures only what 1.5 finished creating.
- **`docs/DECISIONS.md` D39** records: "Bicep chosen over ARM/Terraform for IaC; env-neutral modules under `infra/bicep/`; verify-don't-assume via throwaway-RG deploy + what-if at Sprint 1.6; non-sensitive outputs only (secrets fetched post-deploy, not emitted)."

Phase split:
- **Phase A (agent):** write Bicep modules (decompile from `az group export` as a starting point, then refactor into clean per-resource modules); run `bicep build` to validate; write the operator walkthrough guide at `docs/guides/1.6-iac-capture-bicep.md` covering the throwaway-RG deploy + `az resource list` comparison + cleanup; add D39.
- **Phase B (human):** `az deployment group create` to the throwaway RG; compare `az resource list` outputs; verify no secrets leaked into source; delete the throwaway RG; attest in gitignored notes.

---
### Reviewer focus (/wrap-sprint)
- Infosec: deployment token / keys / **storage connection string (D25)** / **App Insights connection string (D24)** stored only as GitHub Actions secrets and in Azure config — never in repo; no public blob access on `finished` beyond what playback needs (revisit in Epic 8); Container App Managed Identity has only the two needed RBAC roles, not over-privileged (D25); RBAC least-privilege.
- DevOps: naming consistent dev vs (future) prod; budget alert actually firing-capable at $15/mo; App Insights ingestion verified (a test event from any source lands and is queryable).
- Solution architect: data stores physically separate from prod (D7); queue is Storage Queue not Service Bus (D6); SWA on Free per D26; App Insights is the single failure sink per D24, not one-per-component.
- Sr dev: retention window is a conscious number, not a default left unread.
- Support: guide is followable; owner knows what each resource is for; owner knows where to look in App Insights when something fails (link saved in `docs/infra` notes).

---

## Sprint 1.7 — Reconcile the live dev RG to the Bicep (bring dev under IaC management)  **[Human, guided]**

*Added after Sprint 1.6's deploy + `what-if` audit. Sprint 1.6 captured the dev landing zone as Bicep and PROVED it faithful two ways (deploy-to-throwaway + `what-if` against live dev). It deliberately did NOT mutate the live dev RG — capture and read-only proof only. Sprint 1.7 is the separate, deliberate step of actually applying the Bicep to `rg-music-slaylist-dev-use2` so dev's resources are tagged `managed-by=bicep` and future dev changes flow through reviewable PRs. Split out as its own sprint because applying IaC to a live environment is a different risk class than authoring it, and deserves its own `/wrap-sprint` review. **Optional / low-priority: does NOT block Epic 1 closure (1.6) or Epic 2 start.** The fresh prod build at Sprint 9.1 does not depend on this — prod starts empty and has none of the reconcile caveats below.*

- As the owner, I want the live dev resources brought under Bicep management (`managed-by=bicep`, `region` tag added) so dev and prod are managed identically and dev drift is caught by future `what-if` runs.

- As the owner, I want the reconcile done with the known caveats handled explicitly (documented in D39 + the 1.6 guide) so applying IaC to a live environment doesn't surprise me.

Acceptance:
- Pre-flight `az deployment group what-if` against `rg-music-slaylist-dev-use2` reviewed; output matches the D39 "known what-if interpretation notes" (only safe tag changes, computed-field noise, the accepted action-group decoupling, and the two role-assignment creates). Any NEW unexpected delta STOPS the sprint.
- **Role-assignment 409 handled:** dev's two existing portal-created role assignments (Blob Data Contributor + Table Data Contributor on the storage account, random GUIDs from Sprint 1.4) are deleted first, so the Bicep's deterministically-named assignments create cleanly instead of hitting `RoleAssignmentExists`. Brief RBAC gap on the scale-to-zero placeholder is acceptable (no real workload running).
- `az deployment group create` applied to the live dev RG with `env=dev region=use2 workload=music app=slaylist budgetStartDate=<dev's actual first-of-month start>`. Deployment succeeds.
- Post-deploy verification: dev resources now carry `managed-by=bicep` + `region=use2` tags; the two role assignments are present (deterministic GUIDs); blob soft-delete still 30d, versioning still on, all data intact (D7/D28 — no data-store disruption); budget alert still firing-capable.
- Attestation in gitignored `infra/dev-resources.md`.

Phase split:
- **Phase A (agent):** pre-flight `what-if` review; write/extend the operator walkthrough (`docs/guides/1.7-dev-iac-reconcile.md`) covering the role-assignment deletion, the apply, and the post-deploy verification; confirm no Bicep changes are needed (1.6 already made the templates dev-faithful).
- **Phase B (human):** delete dev's two existing role assignments; `az deployment group create` against the live dev RG; verify tags + RBAC + data intact; attest in gitignored notes.

### Reviewer focus (/wrap-sprint)
- Infosec: the brief RBAC gap during role-assignment swap doesn't expose anything (placeholder app, scale-to-zero, no real data yet per D22 corollary); no secrets enter source.
- Solution architect: applying IaC to live dev does not disturb data stores (D7/D28); the reconcile is tags + RBAC-naming only, not a data-plane change.
- Sr dev: `what-if` reviewed BEFORE apply; the role-assignment 409 is pre-handled, not discovered mid-deploy.
- DevOps: dev now matches the prod-deploy path exactly (Sprint 9.1 parity); `managed-by=bicep` is now truthful for dev.
- Support: owner understands that dev is now code-managed and what that means for future changes (portal edits will show as drift in the next `what-if`).
