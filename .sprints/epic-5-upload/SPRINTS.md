# Epic 5 — Upload & Raw Storage (no transcoding yet)

**Goal:** Build the front half of the loop alone, stopping before transcoding, so it can be confirmed in isolation.

**Exit criterion:** an uploader uploads a file, it lands in raw storage, a `processing` record appears — and stays processing (nothing transcodes yet).

---

## Sprint 5.1 — Input validation  **[Agent + owner decision]**
- As the owner, I want an input allowlist and a max file size so the transcoder isn't handed garbage and nobody uploads a 2GB file by accident.
Acceptance: allowlist + size cap decided (record in BACKLOG resolution) and enforced server-side; clear rejection messages.

## Sprint 5.2 — Upload UI + endpoint → raw blob + processing record  **[Agent]**
- As an uploader, I want to upload a song and see it appear as "processing."
Acceptance: upload UI; API writes raw file to `raw-uploads`; creates Table record in `processing`; filename follows `{title-slug}_{timestamp}_{shortid}.{ext}` (D8); soft "duplicate title?" warning is a nicety, not a constraint.

## Sprint 5.3 — Role enforcement on upload  **[Agent]**
- As the owner, I want only uploaders/admins to upload so listeners can't write.
Acceptance: listener role cannot upload; uploader/admin can; enforced server-side.

---
### Reviewer focus (/wrap-sprint)
- Infosec (lead): upload endpoint authenticated + role-checked; validation server-side not just client; size cap actually enforced; uploaded filename can't be used for path traversal.
- Solution architect: API does NOT transcode inline (D5); raw vs finished areas kept distinct.
- Sr dev: partial/failed uploads don't leave orphaned records or blobs.
- DevOps: writes go to dev storage; large-upload behavior understood.
- Support: uploader sees clear processing/failed feedback.
