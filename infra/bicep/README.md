# `infra/bicep/` — Infrastructure as Code

Bicep templates that capture the dev landing zone (Epic 1) and will redeploy as prod (Sprint 9.1) with `env=prod` parameter substitution.

**Why Bicep:** see `docs/DECISIONS.md` **D39**.

**How to validate / redeploy:** see `docs/guides/1.6-iac-capture-bicep.md`.

## Layout

```
infra/bicep/
├── README.md           ← this file
├── main.bicep          ← orchestrator — deploy this; takes env/region/workload/app/notificationEmail
├── naming.bicep        ← name-generator; single source of truth for the CAF naming pattern
├── observability.bicep ← LAW + App Insights + budget alert
├── swa.bicep           ← Static Web App (Free tier, repo-decoupled per D22 safeguard)
├── storage.bicep       ← Storage account + 3 containers + Songs table + 2 queues + 3 diagnostic settings
├── containerapp.bicep  ← CAE + Container App + system-assigned MI + 2 storage RBAC roles
├── eventgrid.bicep     ← Event Grid system topic + system-assigned MI + diagnostic setting
├── drift-check.ps1     ← read-only drift detector (what-if vs live, noise-filtered → CLEAN/DRIFT)
└── drift-check.bat     ← wrapper that runs the .ps1 with -ExecutionPolicy Bypass (no policy change)
```

## Drift detection

Since Sprint 1.7 the live dev RG is `managed-by=bicep`. To check that the live environment
still matches these templates (i.e. no one portal-clicked a change behind the IaC's back),
make sure `az` is logged into the right subscription, then run — **no arguments needed**:

```powershell
./infra/bicep/drift-check.ps1
```

If PowerShell blocks it with *"running scripts is disabled on this system"* (the default
execution policy), either set the policy once — `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`
— or just use the **`.bat` wrapper**, which bypasses the policy for that single call with no
machine change:

```
infra\bicep\drift-check.bat
```

It runs `az deployment group what-if` (read-only — changes nothing), filters the perennial
what-if noise (computed/read-only fields, unevaluatable `reference()` expressions), and prints
**CLEAN** or the **DRIFT** items to the screen. Exit code 0 = clean, 1 = drift (so a future CI
workflow can gate on it). The budget notification email is auto-detected from the live budget,
so you don't supply it (it must match the live budget, or the budget would show as false drift).

For prod (Sprint 9.1): `./infra/bicep/drift-check.ps1 -Env prod -ResourceGroup rg-music-slaylist-prod-use2 -BudgetStartDate <prod's budget start month>`.

To audit what the check filters out (confirm the noise filter isn't hiding something real),
add **`-ShowNoise`** — it lists every ignored delta in gray before the verdict:

```powershell
./infra/bicep/drift-check.ps1 -ShowNoise
```

**Known limitation (now surfaced, not silent):** what-if can't diff array/reference-typed
properties, so the check can't itself verify the **Container App image/resources/env** or the
**diagnostic-setting categories**. Rather than ignore them, it prints an always-on **REVIEW**
note listing them, so a `CLEAN` verdict never implies "everything checked." Confirm those by eye
if you changed them; the real guard is the "update the Bicep in the same sprint" discipline
(CLAUDE.md guardrail) + code review. Automating the whole check as a scheduled CI job is a
backlog item for Epic 2 (needs the OIDC pipeline).

The templates are **env-neutral** — there is no per-environment folder. The same files build dev, prod, or a throwaway validation RG; the environment is the `env` parameter (`dev`/`prod`/`validate`), not a directory. This is what makes prod (Sprint 9.1) a parameter substitution rather than a separate copy.

## What this captures (Sprint 1.6 baseline)

Everything in the dev RG as of the Sprint 1.5 merge:

- Sprint 1.1: Log Analytics, App Insights, $5/$12/$15 budget alert rungs
- Sprint 1.2: SWA Free with empty repo binding (D22 safeguard)
- Sprint 1.3: Storage account, 3 containers (`raw-uploads`, `finished`, `table-backups`), Songs table, soft-delete + versioning, 3 diagnostic settings
- Sprint 1.4: Container App Environment, Container App with system-assigned MI, 2 RBAC role assignments on storage (Blob Data Contributor + Table Data Contributor), CAE log streaming to LAW
- Sprint 1.5: 2 queues (work + poison), Event Grid system topic with MI, EG diagnostic setting

## What this does NOT capture yet

- **Event Grid subscription + EG MI's queue-role assignment** — deferred to Sprint 7.1, when there's a real consumer to wire it up to. See `docs/DECISIONS.md` Sprint 1.5 deferral notes.
- **Sprint 2.2 SWA deploy gate (`staticwebapp.config.json`)** — that's app-level config, not infra; ships with the SWA app source code.
- **The Container App's real transcoder image** — Sprint 6.1 replaces the public placeholder image. The Bicep takes the image reference as a parameter so prod can be deployed with whichever image is current.

## Secrets posture

The Bicep emits **non-sensitive outputs only**: resource IDs, MI Principal IDs, default hostnames, the (non-secret) Application Insights connection string.

Storage account keys and SWA deployment tokens are explicitly NOT in outputs — retrieve those post-deploy with:

```
az storage account keys list -n <storageName> -g <rg>
az staticwebapp secrets list -n <swaName> -g <rg>
```

…and capture them in the gitignored `infra/dev-resources.md` per existing hygiene rules. This keeps deployment logs and ARM history free of secrets (D17, D32).
