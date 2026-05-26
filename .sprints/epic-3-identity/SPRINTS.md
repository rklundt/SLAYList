# Epic 3 — Identity (Entra + roles, the gate)

**Goal:** Stand up the **custom** Entra auth and the three roles BEFORE any feature exists (D11), so no feature is ever exposed without the gate already in front of it. **This epic strengthens — never replaces — Epic 2's already-deployed Path-A′ auth gate (D22).** When this epic lands, the gate's redirect target swaps from `/.auth/login/aad` (SWA's pre-configured Microsoft provider, trusts any Microsoft account) to a custom Entra provider tied to this app's registration, with the three roles populated from the token. The D22 corollary in `CLAUDE.md` (no real content until role-based authz lands) dissolves on this epic's exit.

**Exit criterion:** you log in on the deployed dev app and it knows your role. The any-Microsoft-account gap from Epic 2 is closed — only family members assigned a role can authenticate; everyone else is rejected.

**Guardrail (D2):** no local passwords, ever. Roles ride in the token; the API enforces them.

---

## Sprint 3.1 — Entra app registration + define 3 roles  **[Human, guided]**
- As the owner, I want the app registered in Entra with `listener`, `uploader`, `admin` app roles.
Acceptance: app registration exists; three roles defined; client/tenant IDs captured for config (as secrets/config, not in repo).

## Sprint 3.2 — Shared family account + role assignment  **[Human, guided]**
- As the owner, I want an admin-created shared family member account assigned a role, since the kids may not have email yet (Model A).
Acceptance: shared account exists; assigned a role; documented how to delete/reassign later.

## Sprint 3.3 — Wire SWA auth; swap the D22 gate to custom Entra; API reads role from token  **[Agent]**
- As a developer, I want the Static Web App login flow wired to the custom Entra app registration (3.1) and the API to read the caller's role from the token on every request.
- As the owner, I want Epic 2's `staticwebapp.config.json` Path-A′ gate (D22) updated in place — the route rule stays; only the redirect target changes from `/.auth/login/aad` (pre-configured AAD, any Microsoft account) to the custom Entra provider's login route. The gate is never absent during the swap.
Acceptance: login works on dev; API has a reusable role-check it applies per request; unauthenticated requests are rejected; the `staticwebapp.config.json` route gate now redirects to the custom Entra provider; verified that a Microsoft account NOT assigned a role to this app registration cannot complete sign-in (the any-Microsoft-account gap from Epic 2 is closed).

## Sprint 3.4 — Login gate + role proof; supersede the D22 corollary in place  **[Agent]**
- As the owner, I want a "must log in" gate and a trivial "your role is X" display to prove the chain end to end.
- As the owner, I want the time-bounded D22 corollary in `CLAUDE.md` (the "no content beyond the trivial skeleton" rule) **superseded in place** at this sprint's `/close-sprint` — rewritten from an active prohibition to a historical note, matching how `docs/DECISIONS.md` entries are superseded (D12 → D19 pattern). Nothing is silently removed; the reasoning and the Epic-2→3 history survive as a visible record.

Acceptance:
- Visiting the app requires login; after login the app shows the resolved role; tested on deployed dev.
- The D22 corollary bullet in `CLAUDE.md` is **superseded in place** — rewritten to a historical note. Suggested wording: *"Historical (Epic 2→Epic 3.4 window): the deployed gate was authentication-only via the pre-configured AAD provider and trusted any Microsoft account, so only the trivial skeleton was allowed behind it. Since Epic 3.4 the gate is family-restricted via the custom Entra app registration + roles; corollary resolved. The parent D22 invariant remains active."*
- The parent D22 invariant bullet in `CLAUDE.md` remains active and unchanged.
- The corresponding InfoSec reviewer check in `.claude/commands/wrap-sprint.md` is similarly superseded in place — rewritten to a one-line historical pointer ("Corollary resolved by Epic 3.4 — see the historical note in `CLAUDE.md`"), not deleted.
- This in-place supersession is noted in `/close-sprint`'s doc-sync step, with a one-line entry in `docs/VERSIONS.md` recording the date the corollary was retired.

---
### Reviewer focus (/wrap-sprint)
- Infosec (lead this epic): role enforced on the API side, not just hidden in the UI; no client-trusted authorization; no secrets in repo; token validated correctly.
- Solution architect: roles independent of login mechanism (so guest-invite/public-provider later is additive); no local-password drift.
- DevOps: auth config supplied via environment config, not hardcoded.
- Sr dev: the role-check is a single reusable mechanism, not copy-pasted per endpoint.
- Support: a logged-out or wrong-role user gets a clear message, not a blank failure.
