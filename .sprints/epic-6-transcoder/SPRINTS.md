# Epic 6 — Transcoder Container

**Goal:** The ffmpeg worker, built and tested in isolation BEFORE the event trigger is wired (Epic 7), so "does ffmpeg work in my container" is debugged on its own. **The image build/push/deploy plumbing is proven on a trivial placeholder container FIRST (Sprint 6.0)** — the transcoder's equivalent of Epic 2's "prove the pipeline on something dumb before adding real logic."

**Exit criterion:** hand the container a raw file (manual trigger) → it produces a finished song and updates the record.

**Guardrails:** Container App, ffmpeg in the image (D4). Opus default / AAC fallback (D9) — decide the single output here.

**Scope note:** Sprint 6.0 covers the **dev** image pipeline only. The prod image pipeline lands in Epic 9 alongside `main` → prod (mirrors the dev-then-prod rhythm of Epic 1/9 and Epic 2/9). Once 6.0 lands, 6.3 may simplify or fold into 6.2 — left for Epic 6's own planning pass to decide.

---

## Sprint 6.0 — Container image build/push/deploy pipeline (placeholder container)  **[Both]**

*Stub sprint — surfaced now to make the dependency on a working image pipeline visible from the start. Detailed scoping (registry choice — ACR vs. GHCR vs. Docker Hub; tagging convention; revision-update mechanism; placeholder container shape — "exit immediately" vs. "stays up briefly with a /health endpoint") is deferred to Epic 6's own planning pass at `/start-sprint`.*

- As the owner, I want the container image build/push/deploy plumbing proven on a trivial placeholder image so that when 6.1's real ffmpeg logic lands, it goes into a pipeline that already works.
- As a developer, I want a workflow that builds a Dockerfile, pushes the image to a registry, and updates the dev Container App revision on push to `develop`, so the same plumbing that ships frontend+API in Epic 2 has an image-side counterpart.

Acceptance (high-level — detailed scoping at sprint planning):
- A registry choice is made and recorded in `docs/VERSIONS.md` + `docs/DECISIONS.md`.
- A GitHub Actions workflow builds a placeholder Dockerfile, pushes the image, and updates the dev Container App revision.
- The placeholder container runs end-to-end on the dev Container App via that workflow on a push to `develop`.
- Depends on: Epic 1.4 (dev Container App environment exists). Does NOT depend on: Epic 3 (transcoder is back-end, not user-facing — D22 applies to user-facing environments).

Reviewer focus added to this sprint at planning time. Prod image pipeline = Epic 9.

---

## Sprint 6.1 — Transcode logic  **[Agent]**
- As a developer, I want the worker to read a raw file, transcode to the chosen format, write to `finished`, fill format/size/duration, and flip the record to `ready` — or `failed` on error.

Acceptance:
- Given a raw file + record id, produces finished audio and a `ready` record; on bad input sets `failed`; output format decided (record in BACKLOG resolution + VERSIONS).
- **Originals are NEVER deleted (D28)** — the `raw-uploads` blob is left intact after successful transcode. No cleanup of the raw side ever, full stop. The previous "decide keep-vs-discard original (lean discard)" question is **resolved by D28** and removed.
- **Transcoder filename + stderr discipline per D32 (pick one mitigation):**
  - **(a, preferred):** download the raw blob to a local path named after the **`songId`** (not the human-readable filename), run ffmpeg against the songId-named local file, then write the human-readable finished name into the `finished` container at the end. ffmpeg's stderr only ever embeds the songId — no title-slug PII enters App Insights via stderr.
  - **(b, acceptable filter):** capture ffmpeg's stderr to memory, substitute the input filename with the songId in every captured line, then emit the sanitized text. The raw stderr never reaches App Insights.
  - Record which mitigation was chosen and why in `docs/DECISIONS.md` (a sub-bullet under D32, not a new D-entry — D32 already contemplates both).

## Sprint 6.2 — Containerize with ffmpeg  **[Agent]**
- As a developer, I want a Dockerfile with ffmpeg baked in so the worker runs anywhere.

Acceptance:
- Image builds; ffmpeg present; runs the transcode logic; ffmpeg version recorded in `docs/VERSIONS.md`.
- **Codec verification against the chosen base image (D27).** Don't assume "ffmpeg has aac" (general fact) means "our image has aac" (specific fact) — same skepticism D18 applied to the SWA runtime. Run `ffmpeg -encoders` against the actual image and confirm:
  - `libopus` is present (Opus output path);
  - The built-in `aac` encoder is present (AAC fallback path);
  - **`libfdk_aac` is NOT present** (per D27 — its presence in the chosen base image is the signal that the image is the `nonfree` variant and must not be used).
  Record the `ffmpeg -encoders | grep -E '(opus|aac)'` output (or equivalent) in `docs/VERSIONS.md` alongside the ffmpeg version, dated, so the verification is auditable.
- Base image choice (Debian-based, Alpine-based, or community image without nonfree codecs) recorded in `docs/VERSIONS.md` + `docs/DECISIONS.md` if it constitutes a new architectural choice worth documenting.

## Sprint 6.3 — Build/push image, deploy to dev Container App  **[Both]**
- As the owner, I want the image deployed to the dev Container App so it's ready for the event trigger.
Acceptance: image pushed to a registry; dev Container App runs it; manual invocation transcodes a real file end to end.

---
### Reviewer focus (/wrap-sprint)
- Sr dev (lead): failure paths set `failed` (no stuck `processing`); idempotent if the same job runs twice.
- Infosec: container has least-privilege access to storage/table **via Managed Identity (D25), not a connection string** — verify the two RBAC role assignments (Blob Data Contributor + Table Data Contributor) and confirm no storage secret is baked into the image, env vars, or app config; base image reasonably current.
- Solution architect: scale-to-zero preserved (D4); container writes finished + updates Table (D3) — never a JSON file; transcoder authenticates via MI per D25 (no connection string code path).
- DevOps: image build reproducible; registry access via secrets; **the container emits to Application Insights (D24)** — both successful-transcode and failed-transcode events are queryable in the dev App Insights instance.
- Support: a failed transcode produces a diagnosable signal **specifically in App Insights** (provide the KQL query that surfaces transcode failures with the song id + reason) — "diagnosable" is verifiable against a query, not a vague claim.
