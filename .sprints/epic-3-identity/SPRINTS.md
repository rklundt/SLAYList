# Epic 3 — Identity (Entra + roles, the gate)

**Goal:** Stand up the **custom** Entra auth and the three roles BEFORE any feature exists (D11), so no feature is ever exposed without the gate already in front of it. **This epic strengthens — never replaces — Epic 2's already-deployed Path-A′ auth gate (D22).** When this epic lands, the gate's redirect target swaps from `/.auth/login/aad` (SWA's pre-configured Microsoft provider, trusts any Microsoft account) to a custom Entra provider tied to this app's registration, with the three roles populated from the token. The D22 corollary in `CLAUDE.md` (no real content until role-based authz lands) dissolves on this epic's exit.

**Exit criterion:** you log in on the deployed dev app and it knows your role. The any-Microsoft-account gap from Epic 2 is closed — only family members assigned a role can authenticate; everyone else is rejected.

**Guardrail (D2):** no local passwords, ever. Roles ride in the token; the API enforces them.

---

## Sprint 3.1 — Entra app registration + define 3 roles  **[Human, guided]**
- As the owner, I want the app registered in Entra with `listener`, `uploader`, `admin` app roles.
Acceptance: app registration exists; three roles defined; client/tenant IDs captured for config (as secrets/config, not in repo).

**D41 parallel (decide at this sprint's planning):** this app registration + the three role *definitions* are the same kind of Microsoft Graph object the deploy identity is (D41) — equally scriptable, with the same audit + prod-repeatability benefits. Strongly consider provisioning them via a committed, idempotent bootstrap script (a sibling to `scripts/bootstrap-deploy-identity.*` from Sprint 2.1) rather than manual portal clicks. The per-person role *assignment* (Sprint 3.2) stays manual/guided. Also decide here whether this app registration is shared dev↔prod or created per-environment (it interacts with each SWA's custom-provider config) — the same one-vs-two question Sprint 9.x faces for the deploy identity.

## Sprint 3.2 — Shared family account + role assignment  **[Human, guided]**
- As the owner, I want an admin-created shared family member account assigned a role, since the kids may not have email yet (Model A).
Acceptance: shared account exists; assigned a role; documented how to delete/reassign later.

## Sprint 3.3 — Client-side MSAL login; API validates the token for the caller's role  **[Agent]**
> **Re-shaped mid-sprint (D43).** The original plan swapped the SWA edge gate to a custom Entra provider — but custom SWA auth is **Standard-SKU only** (D26 corrected) and this family-only app stays on Free, so auth moved **client-side (MSAL)** with the **API validating the bearer token**. D22 was revised in place (auth at the API, not the edge). SWA built-in auth on Standard is the documented later switch; the `getCaller()` seam keeps it a one-function change.
- As a developer, I want the SPA to sign users in with MSAL against the custom Entra app (3.1) and the API to validate the caller's bearer token and read their role on every request.
- As the owner, I want authentication enforced without paying for Standard — the static shell may be public (the repo already is, AGPL), but every `/api/*` data request requires a valid, role-bearing token (D22 revised).
Acceptance: login works on dev (MSAL sign-in via the custom Entra app; an assigned account completes and its role is displayed); API has a reusable role-check applied per request (bearer-JWT validated — signature/issuer/audience/expiry); unauthenticated / invalid-token `/api/*` requests are rejected (401) by the function itself; a Microsoft account NOT assigned a role cannot obtain a usable token (`appRoleAssignmentRequired` — the any-Microsoft-account gap from Epic 2 stays closed); D22 revised in place + D26 amended + the MSAL/built-in decision recorded (D43).

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
