# Epic 10+ — Enrichment (from the backlog)

Pull items from `docs/BACKLOG.md` and turn each into a sprint as prioritized. Suggested ordering:

1. **Deactivate/soft-delete lifecycle UI** (uploader deactivates own; admin deactivates any; admin hard-delete; admin filter for deactivated, default off). Data model already supports it.
2. **Playlists** with private/shared visibility (shared = within library, never public).
3. **Search** by title and genre.
4. **Admin tooling**: bulk hard-delete of deactivated songs.
5. **PWA manifest polish** + **custom domain**.
6. Much later: **Android wrapper (TWA)**, **CDN**, **DB beyond Table Storage**, **multi-library** (D19/D20 — includes the two-tier admin split), **self-service public-provider login**.

Each becomes its own sprint file here (e.g. `10.1-deactivate-ui.md`) when started, following the same template: user stories, acceptance, reviewer focus. Add new folders `epic-11-...` etc. if enrichment grows large.

### Standing reviewer focus
- Solution architect: every enrichment checks DECISIONS for downstream impact (esp. libraryId / library-scoped authz per D19/D20, D7 separation, D3 Table Storage); flags contradictions.
- Infosec: new surface stays authenticated/role-checked; "shared" never means public.
- Support: features remain kid-usable.
