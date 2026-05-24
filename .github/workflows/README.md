# GitHub Actions workflows

This folder is intentionally empty in Sprint 0.2.

Workflows arrive in later sprints:

- **Sprint 2.2** — `deploy-dev.yml`: build frontend + API + run Vitest (soft-mode until Sprint 4.1) + deploy to dev SWA on push to `develop`. Includes the D22 Path-A′ auth-gate config in the deploy artifact (`staticwebapp.config.json` at the SWA app root). Uses OIDC federation per D30 (no client-secret in GitHub Secrets). Wires the storage connection string (D25) and App Insights connection string (D24) into SWA app settings.
- **Sprint 4.1** — modifies the workflow to harden the test gate (failing tests block merge per D23).
- **Sprint 6.0** — `transcoder-image.yml`: build + push the transcoder container image to the chosen registry, update the dev Container App revision on push to `develop`.
- **Sprint 9.2** — extends `deploy-dev.yml` to a `main` → prod variant; same gate-config-in-artifact discipline (D22).

All workflows authenticate to Azure via OIDC federation (D30) and pin Node 22 via `actions/setup-node@v4` (D18 — runtime + CI parity).
