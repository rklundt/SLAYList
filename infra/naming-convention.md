# Azure resource naming convention

Single source of truth for how every Azure resource in SLAYList is named. Established at **Sprint 1.1** when the first dev resources land. Applied uniformly thereafter; **prod uses the same pattern with `prod` substituted for `dev`** so dev and prod resources are visually and lexically parallel.

This file documents the **pattern**; concrete deployed names live in the gitignored `dev-resources.md` / `prod-resources.md`. Microsoft's [Cloud Adoption Framework (CAF) naming abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) are the authoritative source for the type prefixes used below.

## The pattern

```
<type-abbrev>-<workload>-<app>-<env>-<region-code>
```

| Slot | Value used in this project | Why |
|---|---|---|
| `<type-abbrev>` | Microsoft CAF abbreviation per resource type (see table below) | Industry-standard; instantly recognizable in the portal |
| `<workload>` | `music` | Allows the same Azure tenant/subscription to host other workloads later without name collisions or visual confusion |
| `<app>` | `slaylist` | The app name; matches the repo name |
| `<env>` | `dev` or `prod` | Per D7, environments are physically separate. Names must encode the environment so a dev/prod mix-up is visually impossible. |
| `<region-code>` | `use2` (East US 2) | Azure CAF region abbreviation; encodes the region so a future multi-region deploy doesn't collide (BACKLOG, far future) |

**Concrete example (pattern only, real values gitignored):** the dev resource group follows the pattern `rg-music-slaylist-dev-use2`.

## Resource type prefixes used in this project

These are the CAF-standard abbreviations for every resource type SLAYList currently uses or will use. Sprints add to this table as new types come in.

| Resource type | Prefix | Example pattern | Sprint introduced | Notes |
|---|---|---|---|---|
| Resource group | `rg-` | `rg-music-slaylist-<env>-<region>` | 1.1 | Top-level container for all SLAYList resources in an environment |
| Log Analytics workspace | `log-` | `log-music-slaylist-<env>-<region>` | 1.1 | Backing store for workspace-based App Insights (D24) |
| Application Insights | `appi-` | `appi-music-slaylist-<env>-<region>` | 1.1 | Single failure-observability sink per environment (D24) |
| Static Web App | `swa-` | `swa-music-slaylist-<env>-<region>` | 1.2 | Hosts frontend + managed-functions API; Free tier per D26 |
| Storage account | `st` (special) | see below | 1.3 | Audio blobs + metadata table + table-backups blob (D28, D33) |
| Container App environment | `cae-` | `cae-music-slaylist-<env>-<region>` | 1.4 | Shared environment for the transcoder Container App |
| Container App | `ca-` | `ca-music-slaylist-<env>-<region>` | 1.4 | The transcoder Container App — placeholder image at 1.4, replaced with real ffmpeg image at Epic 6; scale-to-zero; system-assigned MI for storage RBAC per D25 |
| Event Grid system topic | `egst-` | `egst-music-slaylist-<env>-<region>` | 1.5 | Routes blob-created events to the queue |
| (Storage Queue) | — | logical name (e.g. `transcode-jobs`) | 1.5 | Lives inside the storage account; no global uniqueness, no prefix needed |
| Budget | (descriptive) | `budget-music-slaylist-<env>` | 1.1 | Budgets don't have a CAF prefix; descriptive name. Scoped to the RG, NOT subscription (per Sprint 1.1 acceptance) |
| User-assigned Managed Identity | `id-` | `id-music-slaylist-<env>-<region>` | 1.4 (if used) | If we ever attach a UAMI; system-assigned MI on the Container App is the default per D25 |

### The storage-account exception

Storage account names have stricter rules than every other Azure resource:

- 3–24 characters
- Lowercase letters and numbers ONLY (no hyphens, no underscores)
- Globally unique across all of Azure

So the standard `st-music-slaylist-dev-use2` pattern with hyphens is illegal. The applied convention:

```
st<workload><app><env><region-code>
```

Concretely: dev storage is `stmusicslaylistdevuse2` (22 chars — within the 24-char limit). The same workload/app/env/region slots, just hyphenless. If the resulting name is ≥24 chars, drop the `<workload>` segment first, then the `<region-code>`.

## Region abbreviations

| Region | Code | Why used |
|---|---|---|
| East US 2 | `use2` | Default for this project (Sprint 1.1) — broadly cheapest tier, full SWA Free + Container Apps + Storage + App Insights support, low North America latency |

Other CAF region codes (for reference if we ever multi-region): `use` East US, `usw3` West US 3, `usc` Central US, `eun` North Europe, `euw` West Europe.

## What does NOT go in the name

- **Customer / family identifiers** (per D17 hygiene rules — never `slaylist-rayklundtfamily`)
- **Person names** (per D32 PII rules — never `slaylist-rayklundt-dev`)
- **Timestamps or version numbers** (immutable infra, no versioning in the name; Bicep / IaC files would carry versions if we ever add IaC)
- **Secret-derived suffixes** (never embed a token, hash of a secret, etc.)

## Tag every resource

Beyond names, every Azure resource gets these tags so a future `az resource list --tag` query (or a cost-allocation view) can find them:

| Tag | Value |
|---|---|
| `app` | `slaylist` |
| `env` | `dev` or `prod` |
| `workload` | `music` |
| `managed-by` | `manual` (or `terraform`, `bicep`, etc. when IaC lands). The "which sprint created this" provenance lives in git history of `infra/dev-resources.md` and `docs/VERSIONS.md`, not in the tag — keeps the tag stable and avoids re-tagging every sprint. |
| `cost-center` | `personal` |

Sprint 1.1's guide includes the tag set on every resource created.

## Prod-side equivalents

Every Sprint 1.1 dev resource will have a matching `<...>-prod-use2` counterpart at Epic 9, in a separate resource group `rg-music-slaylist-prod-use2`. Per D7, the resources themselves are physically separate; per this naming convention, the names differ only in the `<env>` slot, making it visually unambiguous which is which in the portal.

## Renaming policy

Azure resource names are immutable for most resource types — renaming = recreate + migrate. So:

- **Get the name right the first time.** Sprint 1.1 acceptance includes "verify resource name matches this convention before clicking Create."
- **If a wrong name does land**, recreate the resource rather than living with it. The blast radius of an inconsistent name compounds over a multi-year project.
