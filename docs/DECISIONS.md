# Decisions Log

Why things are the way they are. Each entry is a decision, the alternatives considered, and why they were rejected. **If a sprint tempts you toward a rejected alternative, this file is why you should stop and consult the human first.**

## D1 — Self-hosting, not self-publishing
Considered publishing the kids' songs to Spotify/Amazon via a distributor. Rejected: the goal is private family playback, not money or public distribution, and AI-generated audio raises copyright/distribution complications that are irrelevant to a private library. Self-hosting sidesteps all of it.

## D2 — Entra ID, no local passwords
Considered local username/password. Rejected: storing/handling passwords correctly is a security footgun and throwaway work. Entra gives identity + roles for free, and roles are independent of how login happens. Family starts with an admin-created shared member account (Model A); guest-invite path exists for later per-kid accounts.

## D3 — Table Storage for metadata, NOT a shared JSON file
Considered a single JSON index file in blob storage. Rejected: two writers (API on upload, transcoder on completion) plus a single shared document forces a whole-catalog write lock. Considered fixing that with blob leases (pessimistic lock — deadlock risk, wrong for low contention) and ETags (optimistic — workable but still locks the whole catalog and needs retry code). Table Storage dissolves the problem: per-record writes never collide, for ~the same cost. Start here; don't "simplify" back to JSON.

## D4 — Container App for transcoding, NOT Function or App Service
- Consumption Function: cheap and scales to zero, but ffmpeg (native binary) is fiddly to package and there are execution-time limits.
- App Service: full power but always-on billing, no clean scale-to-zero. Considered an admin "stop/start the App Service Plan" toggle — rejected: stopping the app doesn't stop plan billing (you'd have to delete/recreate the plan), and it reintroduces a babysitting/foot-gun problem.
- **Container App (chosen)**: ffmpeg baked into the image (trivial), more headroom, AND scales to zero (idle cost ≈ nothing). Best of both.

*Which ffmpeg ships in the image is constrained by licensing — see **D27** (libfdk_aac is forbidden).*

## D5 — Async transcoding via event chain, not inline
The upload API does NOT transcode inline (slow, would freeze the UI, hits Function/HTTP limits). Instead: raw file lands → Event Grid → queue → Container App. The queue adds retry-on-failure (failed jobs retry, then dead-letter into the `failed` state) and is the scale-from-zero trigger. Blob storage cannot call compute directly, which is why Event Grid is required (a Function is NOT required as a middleman).

## D6 — Storage Queue to start, not Service Bus
Service Bus is heavier (ordering, topics, richer semantics) and unnecessary at family scale. Storage Queue is simpler and cheaper. Service Bus is a known upgrade path only if outgrown.

**Dead-letter is app logic, not a queue setting.** Azure Storage Queues have no native dead-letter queue primitive. The "retry + dead-letter → `failed`" behavior promised in Epic 7.2 is **application logic in the transcoder**: track each message's dequeue count, and when it exceeds a configured maximum, move the message to a separate poison/dead-letter queue and flip the record to `failed`. There is no portal toggle for this — do not go looking for one. **This is a concrete upgrade trigger:** Service Bus *does* have a native DLQ with max-delivery-count built in. Needing real dead-lettering without hand-rolled logic — or needing ordering, topics, sessions — is the specific signal that extends D6's "only if outgrown" clause into "outgrown now."

## D7 — Dev and prod data stores physically separate
Considered sharing one storage account / one queue / one Container App with internal separation (different containers/channels). Rejected for anything holding data: blast radius. A dev mistake must never be able to reach the kids' real songs. Compute/routing may be logically split; Static Web App's built-in staging environment is fine; Container App uses two separate apps. Empty dev resources cost ~nothing.

## D8 — Filename is plumbing; title is metadata
Considered making the blob filename human-meaningful and unique via a timestamp. Rejected as the *uniqueness* mechanism: two same-second uploads collide. Chosen: `{title-slug}_{timestamp}_{shortid}.{ext}` — timestamp is for human readability/sorting during restore, the shortid guarantees uniqueness. Titles live in metadata; two kids can both have a "Dragon Fight." A soft "you already have a song called that" warning is a human nicety, not a storage constraint.

## D9 — Opus preferred, AAC fallback
Opus = smaller, open, great quality-per-KB; plays in modern browsers incl. recent Safari/iOS. AAC/.m4a = max compatibility for older Apple devices. Pick one as the consistent output in Epic 6; keep input allowlist permissive.

*Encoder choice for each format is constrained — see **D27**. Short version: `libopus` for Opus, ffmpeg's built-in `aac` for AAC. Do NOT reach for libfdk_aac "for quality" — it's non-free and breaks D15.*

## D10 — No CDN now
Family-scale repeat plays are handled by browser caching (proper cache headers), which is the real egress saver. CDN is the many-listener-scale upgrade and can be added in front of blob storage later without re-architecting.

## D11 — Auth and pipeline come BEFORE features
Original phase plan put login at the end. Moved to the front: an open upload endpoint on the internet is an unauthenticated write path. The pipeline is proven on a trivial "walking skeleton" before any features exist, so feature bugs and infra bugs are never debugged simultaneously.

*This is the sequencing rule (build order). The matching runtime invariant — "no environment publicly reachable without auth, from first deploy, in every environment" — is **D22**. D11 and D22 cross-link; neither replaces the other.*

## D12 — tenantId everywhere, build single-tenant *(superseded by D19)*
Multi-tenant is deferred (the likely future is more *listeners*, not more tenants). But every record carries a `tenantId` from day one so the eventual soft-tenancy path is a near-free data-model decision, not a brutal rewrite. Never write code that assumes one family.

*This entry is preserved for history. The field is now `libraryId` and the concept "tenant/tenancy" is replaced by "library" throughout — see **D19** for the rename and the reason.*

## D13 — PWA-shaped from the start
The Android Play Store app (if ever built) is a thin wrapper (TWA) around the PWA, not a separate native codebase. Building PWA-shaped now (responsive, manifest, Cache API) costs little and means no replatform later. The Cache API work doubles as the egress-saving local audio cache.

## D14 — Human merges; the agent prepares
The agent branches, pushes, and opens PRs with full descriptions, and surfaces merge conflicts as an agent/human consult (proposes resolutions, human confirms). The merge click itself is human — it's the moment of consequence and a cheap place for a human glance. Same for main→prod.

## D15 — AGPL-3.0-or-later, public repo
The repo is public; the running app is private (login-gated, family-only). License is **GNU AGPL-3.0-or-later**, full FSF text in `LICENSE`. Considered MIT/Apache-2.0 (too permissive — wouldn't force a SaaS fork to share back) and "all rights reserved" (incompatible with publishing the source). Considered plain GPL-3.0 (silent on the network-service case — AGPL's § 13 closes that gap). AGPL costs evaluated and accepted: iOS App Store distribution would be friction (Android via TWA is fine — the documented mobile path); future relicensing requires contributor consent (mitigated by D16). Every source file carries a two-line SPDX header (`Copyright (c) <year> Ray Klundt` + `SPDX-License-Identifier: AGPL-3.0-or-later`); missing headers are a `/wrap-sprint` finding. AGPL § 13 obligates the deployed UI to offer users a link to the corresponding source — handled in the running app (footer link to the public repo) by the time Epic 8 ships.

*The "public repo + committed Dockerfiles" half of this posture has a concrete codec consequence in the transcoder — see **D27** (libfdk_aac is forbidden because its binary form is not redistributable).*

## D16 — Contributor terms: DCO + relicensing grant, no CLA bot
Outside contributions are not expected, but if they arrive, the inbound license matters. Considered: GitHub default "inbound = outbound" (gets us AGPL rights but no relicensing option), a full CLA with a bot like CLA Assistant (overkill for a family repo, adds infra), and a plain DCO (proves authority but does NOT grant relicensing). Chosen: **DCO + an explicit relicensing grant**, both acknowledged by a `Signed-off-by` line and documented in `CONTRIBUTING.md`. Lightweight (no bot, no signed paperwork) and gives the maintainer the option to relicense the whole codebase under any OSI-approved license later without tracking down past contributors. PRs without sign-off don't get merged.

## D17 — Public repo from the first commit; private app
The repository is public from commit one — there is no private window during which "we'll clean it up later." Considered starting private and flipping to public after Epic 0 or after launch; rejected because (a) AGPL's force-open clause only matters if the source is actually available, (b) a "we'll scrub it later" mode invites secrets/family-detail leakage that's permanent in git history once the repo flips, and (c) committing publicly from day one creates the right hygiene reflex from the start. The **app** stays private (login-gated via Entra, family-only) — public source does not change who can listen. Hygiene rules in `docs/DEVELOPER_GUIDE.md` (no secrets, no real Azure resource names, no family-identifying detail) apply from the first commit. Sprint 0.1's acceptance criteria include a hygiene scan and a correct `.gitignore` *before* `git init`.

## D18 — Node 22 LTS, single version across the repo, npm workspaces *(npm-workspaces portion superseded by D34; Node 22 + single-version-everywhere parts remain active)*
Frontend, API, and transcoder all pin **Node 22 LTS**. npm workspaces is the monorepo strategy (Static Web Apps' build pipeline expects npm by default; avoids Epic 2 friction). The binding constraint is Static Web Apps managed-functions, which GA-supports `node:22` (verified 2026-05-24 against `learn.microsoft.com/azure/static-web-apps/languages-runtimes`, last updated 2026-02-25 at the time of verification; the older `apis-functions` constraints page is stale and disagrees — the languages-runtimes page is authoritative). Node 20 is also GA but Node 22 LTS has the longer support runway. Node 24 is preview on standalone Functions and not listed for SWA; not a candidate for pin. One Node version across all packages keeps the local-dev story simple and removes a class of "works on the frontend, fails in CI" bugs.

## D19 — `libraryId` everywhere (renamed from `tenantId`), build single-library; supersedes D12
The application-level field formerly called `tenantId` is renamed to **`libraryId`**, and the concept "tenant/tenancy" is replaced by "library" throughout the app's vocabulary. Reason: "tenant" collides with Azure/Entra terminology (the Entra tenant ID is an unrelated, well-defined Azure concept) and the collision caused real confusion. The new field is purely an application-level label for *which music library / household a song belongs to* — no connection to Entra tenants or Azure subscriptions. Type: plain `string` (no branded type; overkill for now). Default value for the single-library case today: `'slaylist-home'` — generic, not PII, safe to commit. The substance of D12 stands: multi-library is deferred (the likely future is more *listeners*, not more libraries), but every record carries `libraryId` from day one so the soft multi-library path is later additive, not a rewrite. Never write code that assumes one library. The Entra tenant ID retains its real name in any Entra-specific context (e.g., Epic 3 config) — that is exactly the disambiguation this rename buys.

## D20 — Library-scoped authorization now; two-tier admin model deferred
Roles stay exactly as defined: `listener | uploader | admin` — no platform/global admin role is built today. Reason: a vestigial over-powered global role with no second library to administer is dead weight and an InfoSec liability. But every authorization check is written as **"can this person do this *within this `libraryId`*"** from day one, even though `libraryId` is always `'slaylist-home'` today. Never write a check that assumes global cross-library reach. Today's single `admin` is implicitly the admin **of the one library** `'slaylist-home'`. **Deferred design (recorded so the insight isn't lost):** when multi-library is implemented, the `admin` role splits into a **library-scoped admin** (manages one library, cannot see others) and a **platform/global admin** (manages the app across all libraries). That split also requires a library-membership concept (which users belong to which library, in which role) and library-context-aware authorization. The full apparatus is cheaper to build later — once a second library is real — than to carry now for no present benefit. This decision is the auth-side complement to D19: scoping checks off `libraryId` from day one makes the second admin tier later an *addition*, not a rewrite.

## D21 — Owner identity: store stable id + display name + creator-kid as separate fields
A song's "owner" answers three different questions, and conflating them was an early mistake — separated cleanly here. Three fields:
- **`ownerOid`** — the Entra `oid` claim. Stable, opaque, never changes for a given identity. **This is the only field used for authorization** ("can this person delete/modify this song"). Never key authz on a username or display name. The `Oid` suffix makes the source and the authz role explicit and pairs cleanly with the display field.
- **`ownerDisplayName`** — the Entra `preferred_username` claim (often an email/handle). For display only. Never used in any authz decision.
- **`createdByKid`** — optional, free-text application metadata: which kid actually made the song, distinct from which login uploaded it (a parent may upload on behalf of a kid). Answers the "who made it" question, not "who owns the record."

Considered keying ownership on `preferred_username` (rejected: changeable, can collide on rename) and storing only the oid (rejected: every list view would need a token-to-name lookup, or names would never render). Public-repo implication: `ownerDisplayName` values are PII and **never** appear in committed fixtures, seeds, or tests — only fake names there (see `docs/DEVELOPER_GUIDE.md` "Public-repo hygiene"). `ownerOid` is opaque and could theoretically be committed without leaking identity, but the same hygiene rule applies for consistency.

## D22 — No environment publicly reachable without authentication, from first deploy
**Runtime invariant (project-level, every environment, forever):** *No deployed environment is ever reachable on the public internet without authentication in front of it — from the very first deploy, in every environment.* This is the runtime corollary to D11's sequencing rule ("auth before features") — same spirit, sharper expression. D11 says when to build auth; D22 says what must be true the moment something is deployed. They cross-link; neither replaces the other.

**Why a separate entry, not a clarification under D11:** D11 reads as a build-order rule. The invariant is a runtime/deployed-state rule a future agent must hit when planning *any* deploy in *any* epic — Epic 2's dev deploy, Epic 9's prod deploy, an Epic 10+ new environment. Burying it inside a sequencing-titled entry would put it where future-you wouldn't look.

**The Epic 2 mechanism (Path A′):** Epic 2's deploy ships a `staticwebapp.config.json` that requires authentication on every route via SWA's built-in route gate, using the pre-configured Microsoft (AAD) identity provider as the redirect target:

```json
{
  "routes": [{ "route": "/*", "allowedRoles": ["authenticated"] }],
  "responseOverrides": { "401": { "statusCode": 302, "redirect": "/.auth/login/aad" } }
}
```

Considered (a) "SWA staging environments are anonymous-reachable by default, so accept the gap and close it in Epic 3" — rejected, this is exactly the "ship open, secure later" anti-pattern D11 exists to kill. Considered (b) "pull Epic 3.1 (custom Entra app registration) forward into Epic 2" — rejected as a Path-A′-equivalent that costs more (real Entra portal work, secrets, complicates Epic 2's "just prove the pipeline" mission) to protect a "hello world" page. Path A′ wins: the gate is real, present from the first deploy, configured in code, available on SWA Free tier, and *evolves* — Epic 3 just swaps the redirect target from `/.auth/login/aad` (pre-configured) to `/.auth/login/<custom-provider-name>` (custom Entra app) when the custom registration lands. The gate is never absent; it only strengthens.

**The temporary corollary that makes Path A′ safe (lives until Epic 3.4 supersedes it in place):** The pre-configured AAD provider trusts *any* Microsoft account, not just family members. So the Epic-2-era gate is **authentication-only, not authorization-restricted**. This is acceptable *only because nothing sensitive ships behind it*. Specifically: until Epic 3's role-based authorization is live, no environment may serve anything beyond the trivial skeleton — no song data, no upload, no real content, no real records, no listable lists of anything meaningful. The "hello world" page and the trivial `/api/health` endpoint are the entire allowed surface. If a future sprint tried to land real content before Epic 3 closed authorization, the any-Microsoft-account gap would suddenly matter — so the rule lives as a guardrail in `CLAUDE.md` and as a reviewer check in `/wrap-sprint` until Epic 3.4 closes the gap. **At that point the corollary is superseded in place — rewritten from an active prohibition to a historical note (same pattern this file uses for superseded decisions, e.g. D12 → D19) — NEVER silently deleted.** The parent invariant remains active forever; the corollary remains visible as a record of the Epic 2→3 window. Rationale: a self-deleting guardrail is a risky pattern — it can fire early (3.4 marked done before the swap fully takes) or the removal logic itself can misfire (a later agent strips a rule that should still apply). Supersession-in-place removes both failure modes.

**Applies to prod, too (Epic 9):** Prod's first deploy (`main` → SWA production environment) must already have role-based auth wired (Epic 3 is a prerequisite for Epic 9 — the existing dependency shape in `INDEX.md` reflects this). Prod never gets a Path-A′-style "any-Microsoft-account" gap; it inherits the full Entra app registration + roles from Epic 3.

## D23 — Vitest as the testing framework; soft-mode CI in scaffolding, hardened at Epic 4.1
**Framework:** [Vitest](https://vitest.dev/). It is the Vite-native choice (we use Vite for the frontend per D18), runs the same TS toolchain end-to-end (no separate Babel/Jest config), is fast (ESM-first), and has a familiar API. Considered Jest (older, heavier config, slower on TS, less alignment with Vite) and node:test (too minimal — no watch UI, weaker mocking). Vitest wins on alignment and ergonomics.

**Pinned from Sprint 0.2** — when shared types first land. The first real code is born testable; no retrofit pass. Test files co-located (`*.test.ts` next to the source) unless a package explicitly diverges. Root `package.json` exposes `npm test` running Vitest across all workspaces.

**CI test gate — soft-then-hard:**
- **Epics 0–3 (scaffolding phase, including auth gate): SOFT.** Epic 2's pipeline runs the tests on every push; red/green is visible in the Actions log and on the PR; but a failure does **NOT** block the merge. Rationale: during scaffolding the velocity cost of a hard gate exceeds the protection it offers — there's almost nothing to regress yet. Tests still get written where useful; they just don't gate.
- **Epic 4 onward: HARD.** Failing tests block merge to `develop`. Rationale: Epic 4 is when real, durable code starts landing (metadata model, API CRUD). Regression risk crosses the threshold where tests must enforce, not advise.

**Critical wiring (matches the supersede-in-place discipline of D22):** "flip the CI test gate from non-blocking to blocking" is an **explicit acceptance criterion in Sprint 4.1**, written into the sprint file as a tracked task — NOT a thing relying on agent memory or the soft→hard date being remembered. This neutralizes the only real failure mode of soft-then-harden: forgetting to harden.

*Implementation note (Sprint 0.3 frontend test setup):* component tests in the frontend workspace use **happy-dom** as the DOM environment (`vitest.test.environment: 'happy-dom'`), alongside `@testing-library/react` for rendering and queries. happy-dom was chosen over jsdom for **faster startup and a smaller install footprint**; it is sufficient for Sprint 0.3's skeleton tests (text rendering, link href, fetch mocking). **Reconsider trigger:** if Sprint 8's real UI work hits a DOM API happy-dom doesn't implement (some SVG corners, certain CSSOM features, edge cases of form validation), flip to jsdom. The flip costs a re-run of every then-existing frontend test against the new environment to catch regressions — non-trivial after Epic 8 lands, cheap before. So: catch it the moment a happy-dom-shaped test failure looks DOM-emulator-related, not weeks later. API workspace tests use Vitest with no DOM environment (Node-only handler functions). Versions pinned via `pnpm-lock.yaml`; ranges in workspace `package.json` files.

*Implementation note (Sprint 0.4 follow-up, 2026-05-24 — Dependabot triage):* happy-dom range bumped from `^15.0.0` to `^20.0.0` (resolved 20.9.0) to remediate three CVEs: **CVE-2025-61927** (Critical — script-evaluation RCE, fixed in 20.0.0), **CVE-2026-34226** (fixed in 20.8.8), **CVE-2026-33943** (fixed in 20.8.9). Breaking changes from v15→v20 reviewed and judged inert for this codebase: v16's parser refactor doesn't affect role/text-based testing-library queries; v17–v19's ESM-only posture matches our `"type": "module"`; v20's headline change — JavaScript evaluation **disabled by default** — is the CVE-2025-61927 fix itself and is safe because our component tests never depend on happy-dom executing `<script>` tags. All 12 tests pass post-bump. The Reconsider trigger above is unchanged.

## D24 — Application Insights as the single failure-observability sink, wired in Epic 1
A budget alert (Epic 1.1) is *cost* observability. **Failure** observability is a separate concern: when a transcode fails, when the queue dead-letters, when the API returns 500, when the deploy errors — where does the human see it? Without an answer, Epic 6/7's reviewer line "a failed transcode produces a diagnosable signal" is unenforceable. Decision: **a single Application Insights instance per environment, wired in Epic 1 alongside the budget alert**, fed by SWA managed functions, the Container App transcoder, and Storage diagnostics. One sink, one place to look. Ingestion cost is trivial at family scale (within or just over the free-tier ingestion quota). Considered separate logging per component (rejected: triples the lookup effort during an incident) and "log to stdout, debug via container logs" (rejected: stdout doesn't follow Storage Queue dead-letter paths, doesn't surface SWA function failures cleanly, and isn't queryable). App Insights' KQL across all three sources is the right shape. Update Epic 6/7 reviewer checks so "diagnosable signal" is verifiable specifically against the App Insights query, not as a vague claim.

## D25 — Storage auth posture: connection string for SWA managed-functions API; Managed Identity for the Container App (platform-forced split)
This is platform-forced, not a preference: per MS Learn `azure/static-web-apps/apis-functions` (verified 2026-05-24), Managed Identity is **available for "bring your own functions" but NOT for managed functions**. Our architecture uses managed functions (D18 + D22's Path A′ both depend on it). The same shared-platform constraint that blocks Managed Identity also blocks **Private Endpoints / VNet integration** for outbound calls from SWA managed functions — both require a per-tenant network/identity plane that the shared SWA managed-functions runtime doesn't expose. This second consequence is the foundation D36 (App Insights public-network-access posture) rests on; recording it here so D25 is the canonical source for "what SWA managed functions can and can't do." So:

- **The SWA managed-functions API reads/writes Blob + Table Storage via a connection string** stored in SWA application settings and mirrored as a GitHub Actions secret for CI. Never in code, never in committed config files. From Epic 1.3 forward, the storage account connection string is a real managed secret — this raises the operational stakes of the existing "secrets never in code or in the repo" guardrail (`CLAUDE.md`) from academic to load-bearing.
- **The Container App transcoder uses Managed Identity** to read raw blobs, write finished blobs, and update Table Storage records. No connection string in the transcoder. RBAC role assignments (Storage Blob Data Contributor, Storage Table Data Contributor, scoped to the dev/prod storage account as appropriate) land at Container App creation.

Future path (deferred, see BACKLOG): **bring-your-own functions** is the documented migration to "Managed Identity everywhere," eliminating the connection-string secret entirely. Not now — it costs (Standard tier + a separate Functions resource to manage) and the connection-string posture is well-understood. Cross-references: D7 (dev/prod stores physically separate — the connection string is therefore environment-specific, never shared), D22 (the secret is part of the deploy artifact's configuration, set via SWA app settings).

**Implementation note (scope of the MI half — added at Sprint 1.5 close):** The MI side of this posture applies to **any Azure resource writing/reading storage from inside Azure**, not just the Container App transcoder. Specifically: **Event Grid system topics** use system-assigned MI for queue delivery (Sprint 1.5 creates the topic + MI; Sprint 7.1 grants `Storage Queue Data Message Sender` RBAC paired with subscription creation). Any future workload that touches storage from an Azure resource that supports MI inherits the same pattern: system-assigned MI + scoped RBAC role(s) on the storage account, never a SAS token, never the storage account key. The "connection-string is for SWA managed functions only" carve-out exists because SWA managed functions are the one platform-shared exception where MI isn't available; everywhere else, MI is the rule.

## D26 — SWA Free tier for both dev and prod now; bumping to Standard for a custom domain is Epic 9's explicit decision
**Both dev and prod on SWA Free for now.** Reasons: zero cost; no dev/prod config divergence; verified-sufficient for the architecture we built (Path A′ gate uses `routes` + `responseOverrides`, both Free-tier features; managed functions support `node:22` on Free per D18). Considered Standard for both (rejected: $9/mo × 2 = $216/year, all to enable features we don't need yet) and Free-dev + Standard-prod (rejected: introduces config divergence between environments, the exact thing D7 told us to avoid for data stores and that the same principle argues for here).

**Standard tier unlocks (none of which we need yet):** custom domains, `networking.allowedIpRanges`, bring-your-own functions, restricted-access preview environments. Of these, **custom domain** is the realistic future trigger — "kids type a memorable URL" rather than "kids type the *.azurestaticapps.net default." That's a real family-UX feature, not a vanity item.

**Epic 9 owns the custom-domain decision explicitly.** Sprint file flags it as a known future fork ("accept the *.azurestaticapps.net URL for prod OR bump prod SWA to Standard for a custom domain"), not something discovered mid-sprint. If chosen, the bump is prod-only — dev stays Free. The dev/prod config-divergence cost is acceptable in that specific case because dev never needs a custom domain.

## D27 — ffmpeg codec licensing — libfdk_aac is forbidden
**Title chosen for findability:** a future agent reaching for `libfdk_aac` (the well-known "higher-quality AAC encoder") needs to land on this entry *before* they add it to the Dockerfile. Burying the prohibition inside D9 (titled around the Opus-vs-AAC *format* choice) wouldn't catch them — they're not necessarily re-reading D9 when they're picking an encoder. So this entry stands alone and is titled after the trap.

**Allowed encoders:**
- **Opus output → `libopus`.** BSD-licensed; ships in every standard ffmpeg distribution; fully compatible with AGPL (D15).
- **AAC fallback output → ffmpeg's built-in `aac` encoder.** LGPL; ships in every standard ffmpeg distribution; fully compatible with AGPL.

**Forbidden: `libfdk_aac`.** It is the higher-quality AAC encoder in theory, but it is **non-free**: building ffmpeg with it requires `--enable-libfdk_aac --enable-nonfree`, and the resulting binary is **not redistributable**. Our Dockerfile is committed to a **public** repository (D15) — shipping a non-redistributable binary recipe in a public repo collides directly with the AGPL/public-repo posture. The "quality gap" argument for libfdk_aac is real only at low bitrates (≤64 kbps); at the bitrates we'll use for family music playback (≥128 kbps stereo, decided in Sprint 6.1), the built-in `aac` encoder is sonically indistinguishable. The trade we are *not* making: a few percent of quality at very low bitrates we won't use in exchange for breaking a load-bearing licensing constraint.

**Practical consequence for the Dockerfile (Sprint 6.2):** any standard ffmpeg base image (Debian-based, Alpine-based, or community images like `jrottenberg/ffmpeg` without the `nonfree` variant) is fine. Specifically: **do NOT use any image variant tagged `nonfree`, `gpl-nonfree`, or that documents libfdk_aac as enabled.** Sprint 6.2 verifies the chosen image actually includes the built-in `aac` encoder (and excludes libfdk_aac) with `ffmpeg -encoders` — the same kind of platform-specific verification D18 did for SWA's Node runtime; "ffmpeg has aac" (general fact) is not the same checkable claim as "our image has aac" (specific fact).

**Cross-references:** this entry sits at the intersection of three decisions and is reachable from each:
- **D4** (Container App with ffmpeg in the image) — establishes that ffmpeg ships in a container image we control; D27 constrains *which* ffmpeg.
- **D9** (Opus preferred, AAC fallback) — establishes the formats; D27 names the encoders for each.
- **D15** (AGPL-3.0-or-later, public repo) — establishes the licensing posture that makes libfdk_aac unshippable; D27 is the concrete codec consequence.

## D28 — Originals kept indefinitely; raw-uploads area IS the canonical archive (overrides the BACKLOG "lean discard" lean)
**Originals are retained forever.** The raw uploaded file is the kids' actual creation; everything downstream (transcoded Opus/AAC, metadata records, derived previews) can be regenerated from it. The transcoded copies cannot regenerate the original. Discarding originals is a one-way door that loses irreplaceable family work the moment a transcode regression, a format change, or a quality-bump motivation lands. Storage cost at family scale is pennies (~10 users uploading occasionally — even hundreds of uploads at ~10 MB each is well under $1/month on Blob Storage Hot tier; orders of magnitude less on Cool/Archive tiers if ever needed).

**Hard guardrail derived from this decision:** the **`raw-uploads` blob area is the canonical archive, NOT transient staging.** No future agent writes a "clean up old raw-uploads" maintenance job, a TTL/lifecycle policy that auto-deletes raw blobs, or a "since the song is `ready`, the raw is unneeded" pruner. That would be deleting the only originals. Lifecycle rules on `raw-uploads`, if any are ever added, are tier-transition only (Hot → Cool → Archive for cost optimization), **never** deletion-class rules. Reflect this in Sprint 1.3's storage account configuration and in `docs/ARCHITECTURE.md`'s description of the raw-uploads area.

Considered (the previous "lean discard" framing): discard raw after successful transcode to save storage. Rejected on the cost/benefit inversion: tiny ongoing cost for keeping vs. irrecoverable loss for discarding, with no operational benefit at family scale. Revisit only if storage ever becomes a material cost line item (estimated: thousands of multi-hundred-MB uploads — not a realistic family-scale scenario).

Cross-references: **D3** (Table Storage as metadata only; the audio file itself is in blob and now explicitly archival), **D8** (filename format is plumbing; the song title lives in metadata — the archive filename's title-slug is for restore readability, the canonical identifier is the shortid), **D33** (Table Storage backup — same "don't lose the kids' stuff" posture extended to metadata).

**Implementation note (scope clarification — added at Sprint 1.5 close):** D28's prohibition targets **automated/scheduled deletion paths**: lifecycle rules, cleanup jobs, programmatic pruners, "since the song is `ready` the raw is unneeded" reapers, anything that runs without an operator at the keyboard. **One-off operator-driven verification operations that upload + immediately delete clearly-marked test artifacts are NOT in scope** — these have an operator present at decision time, run once, leave nothing behind. Sprint 7.1's blob-event-trigger verification is the canonical example: an operator uploads a `_test-event-trigger-<YYYYMMDD-HHMMSS>.txt` artifact to `raw-uploads`, confirms a message lands on the `transcode-jobs` queue, then deletes the test artifact in the same operator session. The `_test-*` prefix marks it as system-internal so `/wrap-sprint`'s D28 check can whitelist the pattern explicitly. If test-artifact buildup ever becomes noticeable (multiple operators / repeated verification runs / forgotten cleanups), formalize a discrete `_test-*` cleanup procedure or move verification to a different storage account — do NOT add a lifecycle rule that pattern-matches `_test-*` (that would be the foot-gun shape D28 forbids).

## D29 — TypeScript strict mode pinned from Sprint 0.2 (root tsconfig: `strict: true` + `noUncheckedIndexedAccess: true`)
The single highest-leverage TypeScript configuration. Without `strict: true` from day one, the codebase accumulates implicit `any`s, null/undefined hazards, and silent unchecked-cast bugs that are expensive to retrofit (every offending site has to be tightened individually under the pressure of "now the build is broken in 47 places"). `noUncheckedIndexedAccess: true` is the second-highest-leverage flag — it catches `array[i]` being possibly `undefined`, which is exactly the bug class that produces "works in dev, NPE in prod with one specific data shape" failures.

**Pinned in the root `tsconfig.json` at Sprint 0.2** when the workspaces structure first lands. All workspaces (`/shared`, `/frontend`, `/api`, `/transcoder`) extend the root via `"extends": "../tsconfig.json"`; no workspace overrides these two flags downward without an explicit reviewer-approved exception (and a comment explaining why).

Considered: leaving strictness off "for scaffolding speed" — rejected, the speed gain is illusory (you write the same code; strict mode just tells you which assumptions are wrong, sooner). Considered: `strict: true` only, not `noUncheckedIndexedAccess` — rejected, the second flag's bug class is exactly the kind that hides in family-scale dev data and surfaces with real users. Cheap to add now; expensive to retrofit.

## D30 — Azure deploy auth via GitHub Actions OIDC federation; NO long-lived service-principal client secret
The deploy credential is the highest-blast-radius secret in CI: it has permission to write to Azure resources. Stored long-lived in GitHub Secrets (the classic "service principal + client secret" pattern), it is a single value that — if leaked, forgotten, or rotated incorrectly — can be replayed indefinitely.

**Use OIDC federation instead.** A dedicated Entra app registration is created for deploy with **federated credentials** keyed to this specific GitHub repository and branch (e.g., `repo:rayklundt/slaylist:ref:refs/heads/develop` and `repo:rayklundt/slaylist:ref:refs/heads/main`). At deploy time, GitHub Actions presents a short-lived OIDC token; Azure validates it via the federation; the workflow gets a short-lived access token scoped to the granted RBAC. **No client secret is ever stored in GitHub Secrets.** Nothing to leak, nothing to rotate.

**Public-repo amplification:** for a public repo, a leaked client secret would be the kind of incident that requires immediate rotation under pressure. OIDC removes the artifact that could leak.

Considered: classic SP + client secret (rejected — high-blast-radius long-lived credential, modern Azure docs explicitly recommend OIDC for new setups since 2022). Considered: SP + certificate auth (rejected — still a long-lived credential to manage; OIDC is strictly better). Free, supported, MS-recommended.

**RBAC scope on the federated identity:** Contributor on the dev resource group (Epic 2); Contributor on the prod resource group (Epic 9). NEVER subscription-scope. Cross-references: **D7** (dev/prod separation — the federation has two role assignments, one per RG, not one over both), **D25** (different scope: D25 is runtime app→storage auth; D30 is CI/CD deploy auth — both follow the "no long-lived secret if avoidable" principle).

## D31 — Public-repo GitHub hardening baseline: secret scanning, push protection, Dependabot, CodeQL — all enabled at Sprint 0.1
Public repos get a set of free GitHub security features that are negligent to leave off:

- **Secret scanning** — detects committed secrets across many providers; alerts on history scans and ongoing pushes.
- **Push protection** — *blocks* secrets at `git push` time before they reach GitHub. This is the critical control: it prevents the permanent-history nightmare that `git filter-repo` after-the-fact only partially mitigates on a public repo (mirrors, forks, indexers may already have the secret).
- **Dependabot security updates** — auto-PRs for dependencies with known vulnerabilities. Per D15/D17 the repo is public and the dep graph is visible; published vulnerabilities apply to us as fast as anyone else.
- **CodeQL code scanning** — SAST for TypeScript; free on public repos; default config is sufficient for our surface.

(Dependabot *version* updates — regular non-security dep refresh — is recommended but optional; can be enabled when dep churn becomes painful to manage manually.)

**Enabled at Sprint 0.1** in the same human-executed pass that creates the repo and configures branch protection — these settings have no meaningful cost (free, near-zero ongoing noise at this scale) and the cost of *not* having push protection is "a secret might already be in your history and you don't know yet."

**IS-4 pair:** the 0.1 guide includes a one-step post-push verification — `gh secret-scanning` (or the equivalent UI check) immediately after the first push, confirming GitHub agrees no secret was detected. If anything is flagged, rotate immediately and remove from history.

Cross-reference: **D17** (public repo from commit one) — these features ARE part of "public repo done right"; not enabling them is a partial implementation of D17.

*Implementation note (Sprint 0.1 close-out):* secret scanning, push protection, and Dependabot security updates enabled successfully at Sprint 0.1. **CodeQL default-setup returned HTTP 404** because GitHub's default-setup endpoint requires detected source languages to configure, and the Sprint 0.1 initial commit is markdown-only. CodeQL retry is tracked as an explicit Sprint 0.2 acceptance criterion (once TypeScript code lands, the endpoint will recognize a language and configure). D31's baseline is unchanged — all four features are required; one is just enabled one sprint later than originally planned.

*Resolution (Sprint 0.2 post-merge):* CodeQL configured successfully against the post-merge develop branch (TypeScript detected). **The correct HTTP verb is `PATCH`, not `PUT`** — the Sprint 0.1 and Sprint 0.2 retry attempts both used PUT, which 404'd for two compounded reasons: (1) Sprint 0.1's repo had no language for the endpoint to recognize anyway, and (2) the verb was wrong even when the language existed. The correct command is:
```
gh api -X PATCH repos/rklundt/SLAYList/code-scanning/default-setup \
  --input <(echo '{"state":"configured","query_suite":"default"}')
```
Verified state: `gh api repos/rklundt/SLAYList/code-scanning/default-setup --jq '.state'` returns `"configured"`. Initial CodeQL scan run queued automatically on configuration. **D31 baseline now 4/4 complete.**

## D32 — No PII in logs: log `ownerOid` not `ownerDisplayName`; log `songId` not `title`; sanitize ffmpeg stderr
D24 made Application Insights the failure-observability sink. Once data lands in App Insights, it is indexed, queryable, retained per the ingestion plan, and difficult to selectively remove. So the "what goes in the log" rule must be tight *before* the first log line.

**Three concrete leak channels at family scale:**

1. **`ownerDisplayName`** — the Entra `preferred_username`, typically an email or handle. PII by D21's explicit framing. **Log `ownerOid` instead** (opaque, non-PII, sufficient for tracing). If a human investigating an incident needs the display name, they can join `ownerOid` to the Table Storage record manually — never put the display name in the log line itself.
2. **Song `title`** — kids name their songs things like "Sophia's Song," "Mom's Birthday Beat," "Ethan vs the Dragon." Titles will contain real first names, family member references, occasional location/event hints. **Log `songId` instead** (uuid-like, non-PII). Same join-at-investigation-time pattern as above.
3. **ffmpeg stderr** — the transcoder captures ffmpeg stderr for diagnostics, but ffmpeg embeds the *input filename* in nearly every line of its output, and the input filename is built from `{title-slug}_{timestamp}_{shortid}.{ext}` (D8). So the title-slug PII rides the stderr capture straight into App Insights. **Two acceptable mitigations** (Sprint 6.1 picks one):
   - **(a)** the transcoder downloads the raw blob into a local path named after the `songId` (not the human filename), runs ffmpeg against the songId-named local file, and renames the *output* to the human-readable finished name at write-to-finished time. ffmpeg's stderr only ever sees the songId.
   - **(b)** the transcoder captures ffmpeg's stderr to memory, substitutes the input filename with the songId in every captured line, then emits the sanitized text to App Insights. The raw stderr never reaches App Insights.

(a) is cleaner — eliminates the leak channel rather than filtering it — and is the recommended default; (b) is acceptable if some upstream constraint requires the human filename for the actual ffmpeg invocation.

**Operational guardrails (also in `CLAUDE.md`):** never use a logging helper that takes "an object" and serializes everything — always log explicit fields, so PII fields can't ride in by default. The `/wrap-sprint` InfoSec check verifies no log statement passes `ownerDisplayName` or `title` (or any field path ending in those) into App Insights telemetry.

Cross-references: **D21** (ownerDisplayName declared PII; the canonical anchor), **D24** (App Insights is the sink), **D7** (dev/prod separate — even dev App Insights gets the same discipline; we do not "relax in dev" because the same code ships to prod).

## D33 — Table Storage backup: nightly export to a separate blob container in the same storage account
Blob Storage has soft-delete + versioning (Sprint 1.3) — accidental deletes and overwrites of audio are recoverable within the retention window. **Table Storage has neither.** No native versioning, no native point-in-time restore. If a bug deletes records (e.g., a faulty cleanup script, a runaway delete-all-where-state=failed query), or if a metadata corruption hits, recovery requires a backup we took ourselves.

**Decision: nightly export of the entire Song table to a `table-backups` blob container in the same storage account.** Implementation in Epic 4 (when the table actually has records to back up — see new Sprint 4.4). Export format: JSON Lines (one record per line) — append-only, easy to diff between days, easy to re-import. Cost at family scale: trivial (a few KB to a few MB per day, retained for a small window).

**Why same storage account, not a separate one?** The realistic recovery scenario at this scale is "bug deleted records" or "operator mistake," not "storage account compromised/deleted." For the latter, a *separate-account* backup is what's needed — that's documented in BACKLOG as a future enhancement (already there). Same-account backup is the right scope now; cross-account is the upgrade.

**Retention:** keep 30 days of nightly backups by default (≈30 small files); tunable in Sprint 4.4 acceptance. Older backups auto-prune via a lifecycle rule on the `table-backups` container — this lifecycle rule deletes *backups* and is fine; it does NOT contradict D28 (which forbids lifecycle deletion on `raw-uploads` specifically).

**Restore procedure documented in `docs/infra` notes at Sprint 4.4 close-out:** how to import a backup file back into the live Table — so a future panicked operator has a checklist, not an improvisation pass.

Cross-references: **D3** (Table Storage as metadata store), **D7** (dev/prod separate — each environment backs up its own table independently), **D28** (originals kept — D33 extends "don't lose the kids' stuff" from audio to metadata).

## D34 — pnpm + pnpm workspaces (supersedes D18's npm choice)
**Switch:** the monorepo uses **pnpm 11.3.0** (pinned via `package.json` `packageManager` field, corepack-compatible) with `pnpm-workspace.yaml` defining the four packages. D18's Node 22 pin and single-version-everywhere principle stand unchanged; only D18's *npm* choice is superseded. Internal workspace deps use the `workspace:*` protocol.

**Benefits accepted (the reason):** pnpm's strict dependency resolution (prevents phantom-dependency bugs — a workspace can only import what it explicitly declares); content-addressable store (faster CI installs at scale); cleaner workspace UX via `workspace:*`; deterministic `pnpm-lock.yaml` distinct from `package-lock.json`.

**Cost accepted (not soft-pedaled):** D18 chose npm specifically to avoid Epic 2 SWA-build friction — SWA's Oryx auto-detects `package-lock.json` and runs `npm ci` for free. With pnpm, Sprint 2.2 takes on extra config — either configure SWA build for pnpm (via `BUILD_FLAGS` to install pnpm before Oryx's npm step), OR install pnpm in the GitHub Actions workflow and bypass Oryx's npm step entirely. D34 is not "D18 was wrong" — it's "we're accepting the cost D18 declined, in exchange for pnpm's benefits."

**Verification is load-bearing, not a formality:** Sprint 2.2 acceptance includes a concrete "verify pnpm + SWA Oryx build works end-to-end on the actual dev SWA deploy" item. If the build proves more painful than expected, that verification is the documented reconsider-point — better caught at Sprint 2.2 than mid-deploy. Same skepticism discipline as D18's SWA-runtime verification and D27's codec verification.

**Implementation notes (from Sprint 0.2 execution):**
- **pnpm requires a filesystem with symlink support.** NTFS on Windows; ext4/APFS on Linux/macOS. exFAT, FAT32, and certain SMB shares fail `pnpm install` with `EISDIR: illegal operation on a directory, symlink ...`. Move the working tree to a supported filesystem rather than reaching for `node-linker=hoisted` (which discards the strict-resolution benefit that justifies D34).
- **pnpm 11 moved most settings out of `package.json`** into `pnpm-workspace.yaml`. Examples in this project: `allowBuilds.esbuild: true` (controls which packages may run postinstall scripts; esbuild needs to install platform-specific native binaries for Vitest). See <https://pnpm.io/settings>. Older `pnpm.onlyBuiltDependencies` in package.json is silently ignored by pnpm 11.
- **Pinned version:** pnpm 11.3.0. Avoid 9.x — it has known Windows install bugs around `@types/node` hoisting that 11.x fixed and (importantly) gave clearer error diagnostics for, including the exFAT-symlink detection above.
- **CI:** `pnpm install --frozen-lockfile` (the pnpm equivalent of `npm ci`) — Sprint 2.2 acceptance.

Cross-references: **D18** (Node 22 pin remains active; only the npm-workspaces portion of D18 is superseded), **Sprint 2.2** acceptance (load-bearing pnpm+SWA build verification), **`docs/DEVELOPER_GUIDE.md`** "Filesystem requirements" section (operationalizes the NTFS/symlink requirement).

## D35 — Azurite required for local Azure Functions dev (storage health check trap)
**Title chosen for findability:** a future contributor running `pnpm dev` will see func's health-check warnings ("Unable to create client for AzureWebJobsStorage") and may not realize *the entire dev stack will crash within a couple of minutes* if storage isn't reachable — even for HTTP-only Functions that don't actually use storage. Discovered the hard way in Sprint 0.3 verification: the previous dev attempt looked fine for a moment, then both API and frontend exited as `concurrently --kill-others-on-fail` killed the stack after func gave up on storage. Documenting as a standalone entry so the trap is named, not buried in the dev guide.

**The trap:** Azure Functions Core Tools (`func`) always tries to create an Azure Storage client at startup, regardless of whether any of the registered functions actually use blob/queue/table storage. It uses this storage for runtime state (timer-trigger schedules, durable functions state, lease management, log retention). The health check fires every 30 seconds and reports `Unhealthy` when the storage client can't be created. After a small number of unhealthy reports the host considers itself non-viable and exits. Even though our `health` endpoint is HTTP-only and never touches storage, the host's existential dependency is unavoidable.

**The decision:** **`pnpm dev` runs [Azurite](https://github.com/Azure/Azurite) (Microsoft's official Node-based Azure Storage emulator) alongside `func` and the Vite dev server, as a third concurrently-managed process.** Azurite binds three ports — 10000 (blob), 10001 (queue), 10002 (table) — matching real Azure Storage's per-service ports. Local config (`api/local.settings.json`, auto-created from `.example` at first run via a prestart hook) sets `AzureWebJobsStorage="UseDevelopmentStorage=true"`, the magic connection string that points `func` at Azurite on those default ports.

**Why this answer over the alternatives:**
- **Run Azurite separately (manual `azurite` in another terminal):** rejected — violates the "one-command local-run" Sprint 0.3 acceptance, and is an easy thing to forget that produces the exact crash the discipline is trying to prevent.
- **Disable func's storage health check via `host.json`:** technically possible (`healthMonitor.enabled = false`), but masks real health issues system-wide and doesn't help once we actually need storage in Epic 4+. The fix-for-now would have to be undone later.
- **Set `AzureWebJobsStorage=""` (empty):** what we originally tried — func still tries to create a client and still fails the health check. Doesn't work.
- **Skip func entirely, use a plain Express server:** rejected per the broader "use `func` because it's the production runtime" reasoning (matches D18 + D34 — local-dev parity with deployed runtime).

**Implementation details (from Sprint 0.3):**
- Azurite is a root devDep (`azurite` ^3.33.0; resolved 3.35.0).
- Data directory is `.azurite/` at the project root, gitignored — safe to delete to reset emulator state.
- Runs as `azurite --silent --location ./.azurite` so it doesn't add log noise to `pnpm dev`'s combined output.
- `dev.sh`'s port-orphan check covers 10000/10001/10002 so a crashed prior run doesn't block the next start.
- When Epic 4+ adds real blob/table code, Azurite is already the local target — no additional setup needed at that point. Production points at real Azure Storage per D7 / Sprint 1.3 (the storage connection string used in `local.settings.json` is replaced by the real one via SWA app settings / GitHub Actions secrets per D25).

**Cross-references:** **D18** (Azure Functions runtime — Azurite is the local stand-in for the storage that runtime always wants), **D34** (`pnpm dev` orchestration — Azurite is one of the three concurrently-managed processes), **D25** (storage auth posture — Azurite uses the `UseDevelopmentStorage=true` magic string locally; production uses the real connection string per D25), **D7** (dev/prod separate — Azurite is the dev-only emulator; never used in or against production).

## D36 — App Insights stays on public ingestion + public query; Private Endpoints deferred until a real trigger
**Decision:** every App Insights instance in this project (dev today, prod at Sprint 9.1) keeps Azure's default *public network access enabled* posture on **both** the ingestion endpoint and the query endpoint. Private Endpoints / Azure Monitor Private Link Scope (AMPLS) are deliberately **not** adopted.

**Title chosen for findability:** a future agent looking at the portal warning "public network access is enabled — restrict?" or reading a security-review checklist that auto-flags "any AI with public endpoints" needs to find *this entry* before reflexively flipping the switch. Hence the decision is named after the trap rather than buried inside D24 (Observability sink).

**Why public stays on:**

- **Ingestion is forced public by our own architecture.** SWA managed functions can't use Private Endpoints — that's exactly the platform constraint D25 documents (and why we use a connection-string secret instead of Managed Identity for the API). Container App on the consumption tier doesn't support VNet integration (only dedicated workload profiles do). Future frontend browser telemetry (Epic 8+) comes from family members' phones and laptops, which are public-internet endpoints by definition. Locking ingestion down would either break the architecture or force every component to a non-Free tier.
- **Query-side restriction breaks the operator workflow.** The Logs blade in the Azure portal routes through the public query API; disabling public query access means an operator can't open Logs from a laptop anymore, and would need a Bastion / jumpbox in an Azure VNet to inspect a failure. RBAC already enforces *who* can query; network restriction adds friction without adding a meaningful protection on top of authn/authz.
- **The real security boundary isn't the network path.** It's the connection-string secret (D25 — managed as a real secret, never in code, rotation procedure in `docs/DEVELOPER_GUIDE.md`), Azure RBAC for query access, D32 PII discipline for what's allowed in the log line in the first place, and LAW retention auto-expiry as data lifecycle. Adding ~$30–100/mo of Private Endpoint surcharges (one PE per service × dev + prod) plus tier upgrades (SWA Standard, Container App dedicated workload profile) doesn't measurably raise that boundary at family scale.
- **Same answer in prod (Sprint 9.1).** Same architecture → same constraints → same conclusion. Sprint 9.1 should mirror this posture without re-debating it; that's the whole point of recording the decision here.

**Considered and rejected:**
- *"Restrict ingestion to private endpoints, accept the cost."* Rejected at family scale — see cost/architecture bullets above. The cost wouldn't be noise.
- *"Restrict query but not ingestion."* Rejected — removes the portal Logs blade for the operator (you) without adding a protection that RBAC doesn't already provide.
- *"Hybrid: dev stays public for cheap operator workflow, prod goes private."* Rejected — the prod architecture isn't different from dev (same SWA tier as currently planned, same Container App scale-to-zero, same browser telemetry source). The forcing constraints are the same, so the right answer is the same. Hybrid would also create dev/prod config divergence (the thing D7 told us to avoid for data, and the same principle argues against for observability config).

**Reconsider triggers** (when this decision should be revisited, not before):
- **(a)** Migration to bring-your-own functions (BACKLOG entry under "Deferred by design") replaces the iKey + connection-string posture with Managed Identity + private networking. At that point Private Endpoints become *genuinely viable* (not just possible-but-expensive) and the cost/benefit flips.
- **(b)** A connection-string leak or repeated abuse incident demonstrates that the secret-management posture isn't holding. The right first response is rotation + tightening secret handling (D25), not network restriction; but if the pattern repeats, network restriction becomes a justified add-on.
- **(c)** Scale grows enough that ~$30–100/mo in private-networking surcharges is noise rather than roughly doubling the entire infrastructure bill.
- **(d)** A regulatory or compliance regime applies to SLAYList that mandates "no public network paths to monitoring infrastructure." Not applicable today (private family use), but a documented future possibility.

**Cross-references:** **D24** (App Insights as the single failure-observability sink — D36 is the network-posture decision on top of D24's existence decision); **D25** (split storage auth — same platform-forcing logic that makes connection strings the right answer for SWA managed functions also makes public ingestion the right answer for AI); **D32** (PII discipline — what's *in* the log is the data-protection layer, more important than the network path the log travels on); **D17** (public repo — same "design for the realistic threat model, not a worst-case bigger than ours" reasoning applies); BACKLOG "Bring-your-own functions for Managed Identity everywhere" (the migration path that would unlock reconsider trigger (a)).

## D37 — SWA deploy auth: OIDC-primary, deployment token as break-glass fallback only (extends D30 to the SWA-specific case)
**Decision:** the Static Web App deploy in Sprint 2.2 (and prod's equivalent in Sprint 9.2) authenticates via OIDC-authenticated `az staticwebapp deploy` commands, NOT via `Azure/static-web-apps-deploy@v1` plus the SWA deployment token. The SWA deployment token captured at Sprint 1.2 serves as a **documented break-glass fallback** — stored in the gitignored `infra/dev-resources.md` only, never in GitHub Secrets, never referenced by any CI workflow, available for ad-hoc manual deploys from a trusted operator's laptop in an emergency.

**Title chosen for findability:** a future agent setting up the deploy workflow will reflexively reach for `Azure/static-web-apps-deploy@v1` (it's the documented Microsoft default for SWA deploys) and may not realize the token-based pattern that action enforces contradicts D30. This entry stands alone and is titled after the trap so it's findable when someone searches for "SWA deploy" or "deployment token."

**Background:** D30 mandates OIDC federation for Azure deploy credentials, with the explicit goal of no long-lived secrets in GitHub Secrets on a public repo (D17). D30 was written assuming the deploy credential was a single service-principal credential. SWA introduces a separate, SWA-specific credential — the "deployment token" — which is NOT a service-principal client secret but IS a long-lived credential capable of authorizing arbitrary deploys to that specific SWA. Reading D30 strictly, it doesn't directly address the SWA deployment token. Reading D30's intent (no long-lived deploy credentials in CI on a public repo), the SWA deployment token IS the kind of credential D30 wants to avoid.

**Why "OIDC-primary, token as fallback" threads the needle:**
- The `az staticwebapp deploy` command is GA on the Azure CLI, works on SWA Free tier (no Standard-tier requirement per D26), and runs under the OIDC-authenticated `az login` session — the same federated identity that ARM operations use. One auth surface for all CI deploy ops, not two.
- Sprint 1.2's acceptance ("deployment token captured for Epic 2") is still satisfied — we capture it. The capture is to *gitignored local notes*, not GitHub Secrets, so the long-lived credential doesn't enter the high-blast-radius surface D30 was designed to shrink.
- We don't lose the break-glass capability: an operator can `swa deploy --deployment-token <token>` from a laptop in an emergency.
- Public repo amplification (D17): the SWA deployment token, if leaked from CI, can be replayed indefinitely to push arbitrary content to the SWA. For a public repo where deploy automation is visible to anyone scraping, the cost of having that token in CI is precisely the risk D30 was designed to avoid.

**Considered and rejected:**
- *(A) Use the SWA deployment token in CI (the `Azure/static-web-apps-deploy@v1` default pattern).* Rejected: contradicts D30's spirit by storing a long-lived deploy credential in GitHub Secrets on a public repo. This is the path-of-least-resistance default that walks back D30 silently the moment it's adopted; the supersede-in-place discipline exists exactly to prevent that drift.
- *(C) Don't capture the token at all.* Rejected: removes a zero-cost break-glass fallback for purity's sake. Sprint 1.2 acceptance explicitly requires capture; the gitignored-local-notes capture is already the safe form, so refusing to capture buys nothing.

**Verification requirement (Sprint 2.2 acceptance, load-bearing):** "`az staticwebapp deploy` via OIDC works on SWA Free tier" is a platform claim. Per the verify-don't-assume discipline used by **D18** (Node 22 runtime support on SWA managed functions), **D27** (ffmpeg codec availability in the chosen base image), **D34** (pnpm + SWA Oryx build), and **D36** (App Insights public-access posture analysis), Sprint 2.2 must **explicitly verify the OIDC deploy path against the actual dev SWA**, not just assume the platform supports it. The specific Azure CLI version verified to work is pinned as a D37 implementation note at Sprint 2.2's `/close-sprint` (today this entry intentionally leaves the version unpinned because the runner image's `az` version is what matters and that's verified at Sprint 2.2, not now). If it doesn't work, the captured deployment token is the documented fallback; this entry would then be *superseded in place* (rewritten from active rule to a historical note pointing at the superseder), NEVER silently abandoned. Same pattern used elsewhere in this file (D12 → D19, D18 → D34).

**Cross-references:** **D30** (general OIDC federation decision this extends to the SWA-specific case); **D26** (SWA Free tier — relevant because SWA tier sometimes gates auth options; `az staticwebapp deploy` works on Free); **D17** (public repo amplification of long-lived secret risk); **D18 / D27 / D34 / D36** (the verify-don't-assume pattern this follows); Sprint 1.2 acceptance (capture the token); Sprint 2.2 acceptance (verify OIDC path, fall back to token only if needed).

## D38 — Storage account public network access stays enabled (extends D36 to the storage-specific case)
**Decision:** the dev storage account `stmusicslaylistdevuse2` (and prod's equivalent at Sprint 9.1) keeps Azure's default *public network access enabled* (Enable from all networks). Private Endpoints / VNet-restricted firewall configurations are deliberately not adopted.

**Title chosen for findability:** a future agent setting up storage (Sprint 9.1 prod, or any future storage account in this project) will see the Azure portal warning *"Enabling public network access will make this resource available publicly"* and reflexively reach to lock it down. This entry stands alone and is titled after the trap so it's findable when someone searches for *"storage public access"*, *"storage firewall"*, or *"storage Private Endpoint"*.

**Background:** D36 (App Insights) and D25 (SWA managed-functions auth posture) establish the principle: SWA managed-functions cannot use Private Endpoints (platform-forced shared infrastructure constraint). D38 extends that principle to the storage account — the SWA managed-functions API reads/writes blobs and tables on this account at Sprint 2.2+, and it can only do so over the public network endpoint (with the connection-string secret per D25 as the auth control).

**Why public access stays on:**
- **Architectural blocker:** SWA managed-functions API cannot reach a Private-Endpoint-only or selected-networks-only storage account. The connection-string-based access path goes through the public endpoint. Locking down storage breaks the deploy.
- **Microsoft doesn't publish SWA managed-functions egress IP ranges** — they're dynamic and shared across the platform. Allowlisting SWA via "Enable from selected networks" therefore isn't feasible. The Azure "trusted services" bypass doesn't include SWA managed-functions either.
- **The real security boundary is the secret, not the network path.** Connection-string secret (D25 hygiene + `docs/DEVELOPER_GUIDE.md` "Secrets — Rotation policy"), Azure RBAC on data-plane operations, **D32** PII discipline for what's in the data, 30-day blob + container soft-delete + blob versioning (Sprint 1.3) for recovery, Storage Diagnostics → LAW for audit (D24's third feeder leg). Network restriction would add ~$15–30/mo in Private Endpoint surcharges with zero practical protection at family scale.

**Considered and rejected:**
- *(A) "Enable from selected networks", allowlist operator's home IP only.* Rejected: breaks SWA managed-functions completely (operator IP isn't SWA; SWA's egress isn't pinnable).
- *(B) "Disable" (private endpoint only).* Rejected: same SWA managed-functions blocker; requires bring-your-own-functions migration to even consider.
- *(C) Use Azure trusted-services bypass + operator IP allowlist.* Rejected: SWA managed-functions aren't on Azure's trusted-services list.

**Reconsider triggers** (same template as D36 + D37):
- **(a)** Migration to **bring-your-own functions** (BACKLOG entry under "Deferred by design") replaces SWA managed-functions and removes the platform constraint. At that point Private Endpoints become *genuinely viable* (not just possible-but-expensive) and the cost/benefit flips.
- **(b)** A connection-string-leak or storage-account-key-leak incident demonstrates the secret-management posture isn't holding. The right first response is rotation + tightening secret handling (D25 procedure), not network restriction; but a recurring pattern justifies network restriction as defense-in-depth.
- **(c)** Scale grows enough that ~$15–30/mo in Private Endpoint surcharges is noise rather than a meaningful percentage of the infrastructure bill.
- **(d)** A regulatory or compliance regime applies to SLAYList that mandates *"no public network paths to data."* Not applicable at family scale.

**Cross-references:** **D24** (App Insights as single failure-observability sink — relevant because Storage Diagnostics is one of its three feeder legs, and what those logs contain is governed by D38's network-posture decision); **D25** (split storage auth posture — D38 is the network-side decision on top of D25's auth-side decision; connection-string for SWA managed-functions, MI for Container App transcoder); **D36** (App Insights public network access — the parallel decision; D38 applies the same logic to storage explicitly); **D28** (raw-uploads canonical archive — the data D38 governs network access for); **D17** (public-repo threat-model framing — same "design for the realistic threat model, not a worst-case bigger than ours" reasoning); BACKLOG "Bring-your-own functions for Managed Identity everywhere" (the migration path that would unlock reconsider trigger (a)).

## D39 — Bicep (not ARM JSON, not Terraform) as the IaC DSL; deploy-time validation against a throwaway RG
**Decision:** Sprint 1.6 captures the dev landing zone in **Bicep** modules under `infra/bicep/dev/`. Prod (Sprint 9.1) is the same Bicep set with parameter substitution (`env=prod`). Validation that the captured templates actually re-create the resources is by **deploying to a throwaway RG and comparing `az resource list` output** against the live dev RG — NOT by export-from-portal round-tripping (which produces noisy diffs from portal-only fields and computed values that don't survive redeployment).

**Title chosen for findability:** a future agent asked to add a resource will ask "where do I capture this — ARM JSON? Bicep? Terraform? Pulumi?" This entry stands alone and is titled after the question so it's findable when someone searches for *"IaC"*, *"Bicep"*, *"ARM template"*, or *"Terraform"*.

**Why Bicep:**
- **First-party Azure tool.** Microsoft-authored, ships in the Azure CLI (`az bicep install`), is the modern replacement for ARM JSON. No third-party state file, no provider plugin, no separate registry account.
- **No state file.** ARM deployments are idempotent against the live RG; there's no `terraform.tfstate` to keep in sync, lose, or guard. For a single-RG-per-env family-scale project this is significant friction removed.
- **Compiles to ARM JSON.** When the abstraction leaks, the compiled JSON is right there (`bicep build`) and readable in the portal's deployment history. No mystery layer.
- **Modules + outputs.** Same DRY composition as Terraform modules — the dev landing zone is six small files orchestrated by `main.bicep`, not one 600-line monolith.
- **AKS/Container Apps API parity.** Newest Azure resource API versions ship to Bicep at the same time as ARM JSON — Terraform's `azurerm` provider often lags by months on niche surfaces like CAE workload profiles and EG system topics with MI.

**Considered and rejected:**
- *(A) Raw ARM JSON.* Rejected: verbose, no modules, no comments, no type help. Bicep compiles to this anyway.
- *(B) Terraform.* Rejected for this project: introduces a state file (extra ops surface), third-party provider that lags Azure on new resource versions, and a separate credential/auth flow. Worth it for multi-cloud or org-scale Azure; overkill for a one-family one-RG-per-env setup.
- *(C) Pulumi / CDK for Terraform.* Rejected: same reasoning as Terraform plus a programming-language abstraction that adds runtime/dependency complexity for negligible benefit at this scale.
- *(D) Portal-export-only (no IaC source-of-truth).* Rejected: exports include computed/runtime fields that don't redeploy cleanly, and the export is read-only — there's no edit-then-apply loop, which defeats half the point. The captured-IaC approach makes prod (Sprint 9.1) a parameter substitution instead of a portal-walkthrough repeat.

**Validation posture (Sprint 1.6 acceptance, load-bearing):** "the Bicep faithfully re-creates the live dev RG" is the claim that must be verified, NOT assumed. Per the verify-don't-assume discipline used elsewhere in this file (**D18**, **D27**, **D34**, **D36**, **D37**), Sprint 1.6 deploys `main.bicep` to a *throwaway RG* (`rg-music-slaylist-validate-use2`), runs `az resource list` against both RGs, diffs the resource types + key properties, attests the parity in the gitignored operator notes, then deletes the throwaway RG. If a real-RG resource fails to materialize from the Bicep, the Bicep is fixed before merge; if it's a property that genuinely cannot be captured (e.g. a portal-only field), that gap is recorded as a known-limitation note rather than silently accepted.

**Secrets posture:** the Bicep emits **non-sensitive outputs only** (resource IDs, MI Principal IDs, default hostnames, non-secret AI connection string). Sensitive material — storage account keys, SWA deployment tokens — is NOT in outputs; operators retrieve those post-deploy via `az storage account keys list` / `az staticwebapp secrets list` and capture them in gitignored notes. This keeps deployment logs and ARM history free of secrets per D17 + D32.

**Cross-references:** **D7** (dev/prod physically separate — Bicep parameter substitution is *exactly* how the "same shape, separate accounts" promise is kept honest); **D17** (public-repo hygiene — Bicep files are committed and therefore must use the pattern-derived naming + placeholder-only sensitive material); **D24** (four-feeder observability sink — every diagnostic-setting wiring in the four feeder legs is captured in Bicep so it can't quietly disappear from prod); **D25** (split auth posture — the Container App's MI + RBAC role assignments are codified in `containerapp.bicep`, not portal-clicked at prod time); **D30** (OIDC federation — the same federated identity that GitHub Actions uses for app deploys also runs `az deployment group create`); **D32** (no secrets in logs — driver of the "non-sensitive outputs only" rule); Sprint 7.1 (Event Grid subscription + MI's queue-role assignment is deferred there; this Bicep deliberately omits both); Sprint 9.1 (prod IaC redeploy — `env=prod` parameter, same templates).
