# Epic 8 — Playback & Listener Experience

**Goal:** The first epic that delivers the actual emotional goal — kids hearing their songs on their devices.

**Exit criterion:** your kids can log in and play their songs on a phone.

**Guardrails:** browser-cache the audio (egress saver + PWA groundwork, D13). Mobile-first.

---

## Sprint 8.1 — Audio player + serve from finished blob  **[Agent]**
- As a listener, I want to play a `ready` song from the library.
Acceptance: player plays finished audio; only `ready` songs are playable; access is authenticated.

## Sprint 8.2 — Browser/Cache-API local caching  **[Agent]**
- As the owner, I want repeat plays served from the device cache so they don't re-hit Azure egress.
Acceptance: correct cache headers; replays serve locally; this lays the PWA caching groundwork.

## Sprint 8.3 — Mobile-first polish  **[Agent]**
- As a kid, I want it to feel good on a phone/tablet.
Acceptance: touch-friendly, responsive; basic PWA manifest so it's installable to the home screen.

---
### Reviewer focus (/wrap-sprint)
- Support (lead): genuinely usable by kids on a phone; clear states (playing, loading, failed).
- Infosec: finished audio access still authenticated/authorized — not a public URL anyone can hit; signed/scoped access as appropriate.
- Sr dev: caching correct (no stale-forever; deactivated songs stop playing).
- Solution architect: PWA-shaped per D13; no desktop-only assumptions blocking the Android path.
- DevOps: egress actually reduced by caching (sanity-check).
