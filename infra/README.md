# /infra

Infrastructure notes, scripts, and (if/when added) IaC for the Azure resources documented in `docs/ARCHITECTURE.md`.

This folder is **intentionally near-empty in Sprint 0.2.** It exists so future epics have a documented home:

- **Epic 1** (Azure landing zone) — naming-convention notes, App Insights link, budget-alert configuration notes; restore-procedure runbooks land here as the resources are created.
- **Epic 4** (Sprint 4.4) — the Table Storage restore-procedure runbook per D33.
- **Epic 6** (transcoder) — container registry choice notes (per Sprint 6.0).

Nothing here is a secret. Real Azure resource names, connection strings, deployment tokens, and Entra app IDs live in GitHub Actions secrets + Azure configuration — never in this folder. See `docs/DEVELOPER_GUIDE.md` "Public-repo hygiene" and D17 / D25 / D30.
