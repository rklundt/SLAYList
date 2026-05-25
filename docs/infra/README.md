# `docs/infra/` — infra notes

This directory holds reference material for the Azure infrastructure that backs SLAYList. It is **part of the public repo** but operates under the same `docs/DEVELOPER_GUIDE.md` "Public-repo hygiene" rules as the rest of the codebase: the *patterns and conventions* are committed; the *actual deployed names, GUIDs, and connection strings* are not.

## What's here

| File | Committed? | Purpose |
|---|---|---|
| `README.md` | ✅ yes | This file |
| `naming-convention.md` | ✅ yes | Microsoft CAF-aligned naming pattern for every Azure resource type we use. Pattern only — no concrete deployed names. |
| `dev-resources.md.example` | ✅ yes | Template for the gitignored dev-environment notes. Shows what to capture; the values are placeholders. |
| `prod-resources.md.example` | ✅ yes (added at Sprint 9.1) | Same shape as dev, for the prod environment. |
| `dev-resources.md` | ❌ **gitignored** | Real dev tenant ID, subscription ID, resource group name, App Insights connection string, instrumentation key, useful KQL queries. Populated locally during Sprint 1.1. |
| `prod-resources.md` | ❌ **gitignored** | Same shape as dev, for prod. Populated locally during Sprint 9.1. |

The split is enforced by the root `.gitignore`:

```
docs/infra/dev-resources.md
docs/infra/prod-resources.md
```

The `.example` templates have NO secrets in them — they're public scaffolding showing what fields to fill in.

## Why this split

Per `docs/DECISIONS.md` D17 (public repo from commit one) and the `docs/DEVELOPER_GUIDE.md` "Public-repo hygiene" rules:

- **Secrets** (App Insights connection string, deployment tokens, storage connection strings): never anywhere in committed files. Real values live in **GitHub Actions secrets** + **Azure app settings** + your **local gitignored notes** — and that's all.
- **Real Azure resource names** (`rg-music-slaylist-dev-use2`, etc.): kept out of committed files. Reduces attack surface for anyone scanning the public repo for "what Azure tenants does this person own?" Real names live in your local gitignored notes + your Azure portal.
- **Tenant ID + Subscription ID**: technically not secrets (they're public-by-design GUIDs that show up in OIDC federation), but for a personal-MSA setup behind a public repo, less attack surface = better. Kept in the gitignored notes too.

What IS in the public files: the **patterns** (`rg-<workload>-<app>-<env>-<regionCode>`), the **conventions** (resource type prefixes, region code abbreviations), and the **structure** of the notes (so future-you or future-collaborator knows what to capture). All of this is generic engineering practice — Microsoft's own CAF docs publish exactly this.

## Adding new infra resources

When a sprint adds a new Azure resource type:

1. Add the resource-type prefix + naming example to `naming-convention.md` (committed). The pattern, not the concrete name.
2. Add a section to `dev-resources.md.example` (committed) showing what to capture about it (resource ID, connection string, etc.). Use placeholders.
3. Add the actual values to your local `dev-resources.md` (gitignored).
4. Reference the resource in code/docs by the GitHub Actions secret name or Azure app setting name — never by its literal Azure name.

## Useful KQL queries

Live in `dev-resources.md` (gitignored) and `prod-resources.md` (gitignored) because they often include resource-specific names. If a query is **truly generic** (e.g., "find all 5xx in the last hour by endpoint"), it can live in a new committed `kql-queries.md` here — but the bar is "no real names anywhere in the query."
