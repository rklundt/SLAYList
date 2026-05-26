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

---
### Reviewer focus (/wrap-sprint)
- Infosec: deployment token / keys / **storage connection string (D25)** / **App Insights connection string (D24)** stored only as GitHub Actions secrets and in Azure config — never in repo; no public blob access on `finished` beyond what playback needs (revisit in Epic 8); Container App Managed Identity has only the two needed RBAC roles, not over-privileged (D25); RBAC least-privilege.
- DevOps: naming consistent dev vs (future) prod; budget alert actually firing-capable at $15/mo; App Insights ingestion verified (a test event from any source lands and is queryable).
- Solution architect: data stores physically separate from prod (D7); queue is Storage Queue not Service Bus (D6); SWA on Free per D26; App Insights is the single failure sink per D24, not one-per-component.
- Sr dev: retention window is a conscious number, not a default left unread.
- Support: guide is followable; owner knows what each resource is for; owner knows where to look in App Insights when something fails (link saved in `docs/infra` notes).
