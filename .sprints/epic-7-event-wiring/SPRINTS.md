# Epic 7 — Event Wiring

**Goal:** Connect the proven upload (Epic 5) and the proven transcoder (Epic 6) via the event chain. Because both halves already work, the only suspect when this misbehaves is the wiring.

**Exit criterion:** upload a song through the UI and watch it go processing → ready automatically, no manual step.

**Guardrail (D5):** blob → Event Grid → queue → Container App. Queue provides retry + dead-letter → `failed`.

---

## Sprint 7.1 — Blob-created → Event Grid → queue  **[Both, guided]**
- As a developer, I want a raw-file landing to emit an event that lands a message on the queue.

Acceptance:
- **Event subscription created** on the Event Grid system topic from Sprint 1.5 (`egst-music-slaylist-dev-use2`):
  - Event-type filter: **`Microsoft.Storage.BlobCreated` only** (we don't care about deletes, updates, or other blob events for the transcode path).
  - Subject filter: `Subject begins with /blobServices/default/containers/raw-uploads/` (so we ignore writes to `finished/` and `table-backups/`).
  - Endpoint type: Storage Queue.
  - Endpoint: `transcode-jobs` queue in `stmusicslaylistdevuse2` (from Sprint 1.5).
  - Authentication: **system-assigned MI of the Event Grid system topic** (NOT a SAS token, NOT the storage account key — same D25 split-auth discipline applied to Event Grid as to the Container App at Sprint 1.4).
- **`Storage Queue Data Message Sender` RBAC role assignment** added on `stmusicslaylistdevuse2`, assignee = Event Grid system topic's system-assigned MI, scope = the storage account. Without this, the subscription's MI auth fails and messages don't land on the queue. **Paired with the subscription creation above** — both land at 7.1, not 1.5, because they're meaningless in isolation.
- **End-to-end verification** (the load-bearing acceptance — verify-don't-assume per D24/D34/D36/D37 and the Sprint 1.4 F2 deferral pattern): upload a tiny test blob to `raw-uploads` via `az storage blob upload --connection-string` (the *upload-test* auth via 1.3's captured connection string is fine; the *Container App's* future auth posture is what D25 protects from connection strings), wait ~1–2 min for Event Grid delivery, then peek the `transcode-jobs` queue (`az storage message peek` or portal Queue blade) — confirm a message landed with the expected blob path in its payload. Delete the test message + test blob. Record the verification outcome as a one-line note in `infra/dev-resources.md` (gitignored) — same attestation shape as Sprint 1.3's storage diagnostics verification.

Dropping a file in `raw-uploads` results in a queue message (Event Grid subscription validated/handshaked).

## Sprint 7.2 — Container App scales from zero on queue; retry + dead-letter  **[Both]**
- As the owner, I want the Container App to wake on a queue message, process, and on repeated failure dead-letter into the `failed` state — and idle back to zero.
Acceptance: queue message wakes the container from zero; success path completes; failures retry then dead-letter; record reflects `failed`; container returns to zero when idle.

## Sprint 7.3 — End-to-end test through the UI  **[Both]**
- As the owner, I want a real UI upload to flow all the way to `ready` automatically.
Acceptance: UI upload → processing → ready with no manual step; a deliberately-bad upload → `failed` visibly.

---
### Reviewer focus (/wrap-sprint)
- DevOps (lead): scale-from-zero actually triggers; dead-letter path exists and is monitored **via Application Insights (D24)** — a dead-lettered message produces a queryable event with the song id and the last-attempt reason; provide the KQL query; no message stuck invisibly.
- Sr dev: exactly-once-ish behavior acceptable; duplicate delivery doesn't double-create finished files.
- Infosec: event/queue access least-privilege; only intended events processed.
- Solution architect: matches D5 chain; no inline-transcode shortcut crept in; DLQ is the hand-rolled app-logic kind (D6's extension — Storage Queue has no native DLQ).
- Support: failed jobs are observable **in App Insights**, not silent — the owner can answer "what failed last and why?" with a single KQL query, saved and linked from `docs/infra` notes.
