# Architecture

This is the settled architecture. It was arrived at deliberately. Before changing anything here, read `DECISIONS.md` — most "obvious improvements" were already considered.

## The goal (never lose sight of this)

A private, login-gated family music library. Kids upload songs they made, play them on their devices. Not commercial, not public, not for sale. Small now (~10 users, 1–2 uploaders). Should be cheap at rest and not painful to grow.

## Components

```
                         ┌─────────────────────┐
   Browser (kids) ─────► │  Static Web App      │
   - React/TS PWA        │  - React/TS frontend │
   - caches audio        │  - light TS API      │
   locally for replay    └──────────┬───────────┘
                                     │
        login/roles ◄── Entra ID     │ writes raw file,
                                     │ creates "processing" record
                                     ▼
                         ┌─────────────────────┐
                         │  Blob Storage         │
                         │  - raw-uploads area   │──┐ blob-created event
                         │  - finished area      │  │
                         └───────────────────────┘  ▼
                         ┌─────────────────────┐  ┌──────────────┐
                         │  Table Storage       │  │  Event Grid  │
                         │  - song records      │  └──────┬───────┘
                         │  - state, owner, etc. │         │ routes to
                         └─────────▲─────────────┘         ▼
                                   │ flips record    ┌──────────────┐
                                   │ to ready/failed  │  Queue       │
                                   │                  └──────┬───────┘
                                   │                         │ wakes (scale-from-zero)
                         ┌─────────┴───────────┐             ▼
                         │  Container App       │ ◄───────────┘
                         │  - ffmpeg transcoder │
                         │  - scale-to-zero     │
                         └──────────────────────┘
```

## The core loop

1. Uploader (authenticated, role-checked) uploads a file via the app.
2. API validates it (format allowlist, size cap), writes the raw file to the raw-uploads blob area, and creates a Table Storage record in state `processing`.
3. The raw-file-landing emits a blob-created event to Event Grid.
4. Event Grid routes it to the queue.
5. The queue wakes the Container App from zero.
6. The Container App runs ffmpeg, writes the finished Opus/AAC to the finished area, and flips the record to `ready` (or `failed` on error, via retry/dead-letter).
7. The app shows the song as ready; listeners play it, and the browser caches it for cheap repeat plays.

## Why each component (short)

- **Static Web App**: free/cheap hosting for a static frontend + integrated light API; built-in Entra auth; built-in staging environment. Right-sized.
- **Blob Storage**: cheap durable storage for audio. Soft-delete + versioning = recovery net behind app-level deletes. The **`raw-uploads` area is the canonical archive of the kids' work (D28)** — finished/transcoded copies are derivative and can be regenerated; originals cannot, and are retained indefinitely. No deletion-class lifecycle rule ever runs on `raw-uploads`. The `finished` area holds derived copies and can have lifecycle rules in the future without data-loss risk.
- **Table Storage**: near-free key/value store for song records. Per-record writes mean two uploaders never collide — no locking needed. (This is why we did NOT use a shared JSON file.) Note: Table Storage has neither soft-delete nor versioning, so the metadata-loss recovery posture is a **nightly export to a separate `table-backups` blob container in the same storage account (D33)** — implemented in Sprint 4.4.
- **Container App (ffmpeg)**: needs more horsepower and easy native-binary (ffmpeg) packaging than a consumption Function gives, but scales to zero so idle cost ≈ nothing. App Service was rejected: always-on billing, no clean scale-to-zero.
- **Event Grid + queue**: blob storage cannot call compute directly; it emits events. The queue adds retry-on-failure and is the scale-from-zero trigger for the Container App. Storage Queue to start (Service Bus is the heavier upgrade if ever outgrown). **Note:** Storage Queue has no native dead-letter primitive — the "retry + dead-letter → `failed`" behavior in Epic 7 is implemented in the transcoder (max-dequeue-count + a separate poison queue + explicit move logic), not configured on the queue. Service Bus's native DLQ is the concrete upgrade trigger if hand-rolled DLQ becomes painful. See **D6** for the full reasoning.
- **Entra ID**: no local passwords to hold or get wrong. Roles ride in the token.

## Dev / Prod separation

- **Data stores: physically separate** per environment (separate storage accounts → separate blobs AND tables; separate queues; separate Container Apps). Reason: blast radius. Dev mistakes must never reach prod data.
- **Static Web App: use its built-in environments** (production vs. staging) — designed for this.
- **Container App: two separate apps** (dev + prod), not channels in one. Scale-to-zero makes two ≈ the cost of one.
- Branches: `develop` deploys to dev, `main` deploys to prod. Human gates both merges.

## Data model (song record)

| Field | Notes |
|---|---|
| `id` | unique id (also drives the blob short-id) |
| `libraryId` | application-level library label (D19, supersedes D12). Always present; one value today (`'slaylist-home'`); never assume one library. **Not** the Entra tenant ID. |
| `title` | display name; NOT the filename |
| `ownerOid` | Entra `oid` claim of the uploader. Stable, opaque. **The only field used for authorization** — see D21. |
| `ownerDisplayName` | Entra `preferred_username` (display only, never used in authz; PII — see hygiene rules) |
| `createdByKid` | optional metadata: which kid made the song (distinct from `ownerDisplayName`, which is "which login uploaded it") |
| `genre` | for later search |
| `state` | `processing` / `ready` / `failed` / `deactivated` |
| `createdAt`, `deactivatedAt` | timestamps |
| `blobPath` | pointer to finished file |
| `format`, `sizeBytes`, `durationSec` | filled by transcoder |

Filename convention: `{title-slug}_{yyyyMMdd-HHmmss}_{shortid}.{ext}` — readable for restore, unique by shortid.

## Audio format

Opus (smaller, open) is preferred; AAC/.m4a is the max-compatibility fallback for older Apple devices. Transcoder converts all uploads to the chosen output. Decide one as the default in Epic 6; keep the input allowlist permissive, the output single and consistent.

## Caching / cost

- Browser caches finished audio (proper cache headers) → repeat plays don't re-hit Azure egress. This is the primary cost lever.
- No CDN now (family scale doesn't need it; it's the listener-scale upgrade).
- Budget alert turned on in Epic 1 — free insurance against surprises.

## Deferred / growth (do NOT build now, do NOT design out)

- Database beyond Table Storage (only if Table Storage is ever outgrown).
- CDN (only for many-listener scale).
- Multi-library (data model stays library-aware via `libraryId`; build single-library — D19). The two-tier admin model (library admin vs. platform admin) lands with this — see D20.
- Self-service public-provider login for non-family listeners (Entra Model A covers the family now).
- Android Play Store wrapper (build PWA-shaped now; wrap later — no rebuild needed).
- Separate-account backup (soft-delete + versioning covers the start).
- Service Bus (only if Storage Queue outgrown).
