# Epic 7 — Event Wiring

**Goal:** Connect the proven upload (Epic 5) and the proven transcoder (Epic 6) via the event chain. Because both halves already work, the only suspect when this misbehaves is the wiring.

**Exit criterion:** upload a song through the UI and watch it go processing → ready automatically, no manual step.

**Guardrail (D5):** blob → Event Grid → queue → Container App. Queue provides retry + dead-letter → `failed`.

---

## Sprint 7.1 — Blob-created → Event Grid → queue  **[Both, guided]**
- As a developer, I want a raw-file landing to emit an event that lands a message on the queue.
Acceptance: dropping a file in `raw-uploads` results in a queue message (Event Grid subscription validated/handshaked).

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
