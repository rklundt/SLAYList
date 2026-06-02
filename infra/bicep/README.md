# `infra/bicep/` — Infrastructure as Code

Bicep templates that capture the dev landing zone (Epic 1) and will redeploy as prod (Sprint 9.1) with `env=prod` parameter substitution.

**Why Bicep:** see `docs/DECISIONS.md` **D39**.

**How to validate / redeploy:** see `docs/guides/1.6-iac-capture-bicep.md`.

## Layout

```
infra/bicep/
├── README.md           ← this file
└── dev/                ← the dev landing zone; also used for prod via `env=prod`
    ├── main.bicep      ← orchestrator — deploy this; takes env/region/workload/app/notificationEmail
    ├── naming.bicep    ← name-generator; single source of truth for the CAF naming pattern
    ├── observability.bicep   ← LAW + App Insights + budget alert
    ├── swa.bicep       ← Static Web App (Free tier, repo-decoupled per D22 safeguard)
    ├── storage.bicep   ← Storage account + 3 containers + Songs table + 2 queues + 3 diagnostic settings
    ├── containerapp.bicep    ← CAE + Container App + system-assigned MI + 2 storage RBAC roles
    └── eventgrid.bicep ← Event Grid system topic + system-assigned MI + diagnostic setting
```

`dev/` is named after the original capture target, not the deployment target. Prod uses the same files; the directory name is historical and renaming it later would be churn for no benefit.

## What this captures (Sprint 1.6 baseline)

Everything in the dev RG as of the Sprint 1.5 merge:

- Sprint 1.1: Log Analytics, App Insights, $5/$12/$15 budget alert rungs
- Sprint 1.2: SWA Free with empty repo binding (D22 safeguard)
- Sprint 1.3: Storage account, 3 containers (`raw-uploads`, `finished`, `table-backups`), Songs table, soft-delete + versioning, 3 diagnostic settings
- Sprint 1.4: Container App Environment, Container App with system-assigned MI, 2 RBAC role assignments on storage (Blob Data Contributor + Queue Message Processor), CAE log streaming to LAW
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
