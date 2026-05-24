# Backlog

Things deliberately deferred, plus ideas that surface mid-build. This is the parking lot — putting something here means "real, but not now." `/wrap-sprint` and `/close-sprint` may add items here when reviewers spot future work.

## Deferred by design (with a known path forward)

- **Playlists** with private/shared visibility (shared = visible within the library, never public). Epic 10+.
- **Search** by title and genre. Epic 10+. (Table Storage supports this; metadata model already carries `genre`.)
- **Admin experience**: filter deactivated (default off, toggle on), bulk hard-delete of deactivated songs. Epic 10+.
- **Soft-delete / deactivate lifecycle UI** (uploader deactivates own; admin deactivates any; admin hard-deletes). Data model already supports the states.
- **Database beyond Table Storage** — only if Table Storage is ever outgrown.
- **CDN** — only at many-listener scale; goes in front of Blob Storage, no re-architecture.
- **Multi-library** (formerly "multi-tenancy" before D19's rename) — `libraryId` is already threaded through every record (D19), and authorization is already library-scoped (D20), so the soft multi-library path is additive. When this lands, the `admin` role splits into a **library-scoped admin** (manages one library) and a **platform/global admin** (manages the app across libraries), and a library-membership concept is introduced (which users belong to which library, in which role) — see D20 for the deferred design.
- **Self-service public-provider login** for non-family listeners — Entra Model A covers the family now.
- **Android Play Store wrapper** (TWA around the PWA) — build PWA-shaped now, wrap later.
- **Separate-account backup** — soft-delete + versioning covers the start.
- **Service Bus** — only if Storage Queue is outgrown.
- **Per-kid private spaces** via guest-invite Entra accounts — when kids are old enough to want them.
- **Bring-your-own functions for "Managed Identity everywhere"** — the migration path away from D25's split auth posture. SWA *managed* functions can't use Managed Identity (platform limitation); bring-your-own functions can. The migration would eliminate the storage connection string secret entirely. Costs: requires SWA Standard tier per environment, plus a separately-managed Azure Functions resource. Triggered when the connection-string posture becomes painful (e.g., a secret rotation incident, or a desire for a uniform auth story across API + transcoder). Not now.
- **Custom domain for prod** (D26) — bumps prod SWA to Standard tier (~$9/mo) for a memorable family-facing URL. Explicitly Sprint 9.1's decision.

## Open questions to resolve at the right epic

- Opus vs AAC as the single output default — decide in Epic 6.
- ~~Keep the original upload after transcoding (for future re-transcode) or discard to save space — decide in Epic 5/6. (Lean: discard at family scale.)~~ **RESOLVED by D28: originals are kept indefinitely as the canonical archive; raw-uploads area is forbidden to delete from.**
- Exact input format allowlist + max upload size — decide in Epic 5.
- Hard-delete retention window length on Blob soft-delete — decide in Epic 1.
- `ownerDisplayName` freshness — cache once at upload time (stale-name risk on later display) vs. refresh from the latest token on every read (more API churn, plus a minor privacy implication if a user changes their handle and old records leak the old one) — decide in Epic 4.
- **Table Storage schema evolution policy** — additive-only by default; upgrade-on-read pattern for breaking changes. Pin in `docs/DEVELOPER_GUIDE.md` before Epic 4 starts (the first sprint with persisted records).
- **Shared-types deploy coordination across frontend/API (SWA) vs. transcoder (Container App)** — they deploy separately, so a breaking `Song` type change has a window where the two halves disagree. Pin the deploy-order discipline in `docs/DEVELOPER_GUIDE.md` before Epic 6.
- **API error response shape** — pin a single shape (e.g. `{error: {code, message}}` + correlation id, appropriate HTTP status) so endpoints don't drift. Decide in Sprint 4.2.
- **Upload idempotency mechanism** — client-generated idempotency key OR client-generated song id treated as upsert, so a retry after a dropped network does not create a duplicate song. Decide in Sprint 5.2.
- **Audio cache invalidation strategy (PWA / browser cache)** — key on `blobPath + etag/version`, not on `songId` alone, so deactivation and re-transcode invalidate cleanly. Decide in Sprint 8.2.
- **Secret rotation policy** — exact rotation cadence + step-by-step procedure for the storage connection string, SWA deploy token, and App Insights connection string. One-liner is enough; lands in `docs/DEVELOPER_GUIDE.md` "Secrets" section whenever convenient (no sprint dependency).
- **`/api/health` response minimization** — `{status: "ok"}` and a 200, no version/build/environment info. Decide and pin in Sprint 0.3 (frontend health call) / Sprint 2.2 (deployed health) planning.

## Emergent (added during build)

_(empty — agents add here as ideas surface)_
