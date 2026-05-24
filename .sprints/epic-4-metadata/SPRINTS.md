# Epic 4 — Metadata Model & Song Records (no audio yet)

**Goal:** Build the data spine in isolation — much easier to debug than data + files + transcoding at once.

**Exit criterion:** the app lists songs from real metadata, with no actual audio involved.

**Guardrails:** Table Storage, not a JSON file (D3). `libraryId` on every record (D19, supersedes D12); reads and writes are library-scoped (D20). Owner identity follows D21 — `ownerOid` is the only authz key, `ownerDisplayName` is display only. Title is metadata, filename is plumbing (D8).

---

## Sprint 4.1 — Table schema + shared Song type + states; **harden the CI test gate (D23)**  **[Claude Code]**
- As a developer, I want the Table Storage schema and the `/shared` `Song` type to match, with states `processing|ready|failed|deactivated`.
- As the owner, I want **the CI test gate flipped from soft (advisory) to hard (blocking) at the start of Epic 4 (D23)** — Epic 4 is when real, durable code starts landing and regression risk crosses the threshold where tests must enforce, not advise.

Acceptance:
- Schema documented; `Song` type carries id, libraryId, title, ownerOid, ownerDisplayName, createdByKid?, genre?, state, createdAt, deactivatedAt?, blobPath?, format?, sizeBytes?, durationSec?.
- **The CI test gate is HARD from this sprint forward (D23).** Concretely:
  - Remove the `# Soft-mode: ... until Sprint 4.1 hardens this` comment from the GitHub Actions workflow (the breadcrumb left by Sprint 2.2).
  - Configure the workflow so the test job's failure marks the PR check as failed and **blocks merge to `develop`** (branch protection rule on `develop` requires the test check to pass; verify the setting).
  - Add a one-line test in `/shared` covering at least one invariant of the `Song` type (e.g., that `SongState` is exactly the four documented values, that `Role` is exactly the three documented values). This is the smoke test that proves the hardened gate has something to enforce.
  - Update `docs/VERSIONS.md` to record the soft→hard flip with date.
  - Note the supersession in `/close-sprint`'s doc-sync — the soft-mode era is over, recorded as history not erased.

## Sprint 4.2 — API CRUD-ish operations  **[Claude Code]**
- As a developer, I want API operations to create, read, list, and update song records, role-checked.
Acceptance: create/read/list/update implemented against dev Table Storage; list supports filtering out `deactivated` by default; operations respect roles.

## Sprint 4.3 — Barebones list screen from seeded records  **[Claude Code]**
- As the owner, I want a plain "list all songs" screen reading real metadata, seeded with fake records.
Acceptance: screen lists seeded records with title/owner/genre/state; deactivated hidden by default; no audio anywhere yet.

## Sprint 4.4 — Nightly Table Storage backup job (D33)  **[Claude Code]**
- As the owner, I want a nightly export of the Song table to the `table-backups` blob container (provisioned in Sprint 1.3) so a bug, mis-issued delete, or metadata corruption is recoverable. Tables have no native versioning or soft-delete — this backup is the recovery posture.

Acceptance:
- A scheduled job runs once nightly in the dev environment and exports the entire Song table to a single file in the `table-backups` container, named `songs-YYYY-MM-DD.jsonl` (one record per line, JSON Lines format — append-friendly, easy to diff, easy to re-import).
- Implementation mechanism decided at sprint planning (`/start-sprint` proposes): options include a Container App Job on cron schedule, a Logic App, or an Azure Function timer trigger. Pick the simplest that meets the schedule and respects D25's auth posture (Managed Identity if Container App or Function; system-assigned MI if Logic App).
- Lifecycle rule on the `table-backups` container auto-prunes files older than 30 days (this is a backup-pruning rule and is fine — does NOT contradict D28's no-deletion rule on `raw-uploads`).
- **Restore procedure documented in `docs/infra` notes** at this sprint's `/close-sprint`: step-by-step "given a backup file, here's how to import it back into the live Table." Tested at least once during the sprint by exporting, dropping a test record, and restoring it.
- Cost recorded (expected: well under $1/month at family scale; JSONL files are small).

---
### Reviewer focus (/wrap-sprint)
- Solution architect: Table Storage used (no JSON-file regression D3); libraryId present and never assumed-single (D19, supersedes D12); authz is library-scoped (D20), no global cross-library reach; ownerOid is the authz key, never ownerDisplayName (D21); no schema choice that blocks playlists/search later.
- Infosec: list/update role-checked and library-scoped (D20); one library's records not leakable across libraryId; ownerDisplayName never used in an authz decision (D21).
- Sr dev: shared type is the single source of truth; no divergent Song shapes.
- DevOps: operations point at dev storage via config.
- Support: empty/seeded states render sensibly.
