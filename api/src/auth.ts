// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Server-side auth helper for the SLAYList API (Epic 3).
 *
 * The SWA edge layer authenticates the user (custom Entra provider, Sprint 3.3) and
 * injects the signed-in identity into every `/api/*` request as the base64-JSON header
 * `x-ms-client-principal`. This module decodes it into the caller's stable id + app role.
 *
 * Why re-check here when the D22 gate already blocks anonymous at the edge: defense in
 * depth. Authorization is enforced server-side, never trusted from the UI (InfoSec rule).
 * `getCaller` returns null for an unauthenticated request so handlers can reject it.
 *
 * `Role` is imported as a TYPE ONLY (erased from the compiled JS) so this carries no
 * runtime dependency on `@slaylist/shared` -- keeping the deployed function's flat
 * node_modules clean (Sprint 3.1.5) while the shared type stays the single source of truth.
 *
 * PII discipline (D32): the only identity field used for authz/logging is `ownerOid`
 * (the opaque, stable Entra object id, D21). Never read or log displayName / email.
 */

import type { HttpRequest } from '@azure/functions';
import type { Role } from '@slaylist/shared';

export interface Caller {
  /** Stable Entra object id (`oid`). The ONLY identity field used for authz + logs (D21/D32). */
  ownerOid: string;
  /** The caller's app role from the token's `roles` claim, or null if none is present. */
  role: Role | null;
}

const PRINCIPAL_HEADER = 'x-ms-client-principal';
// The object-id claim type varies by token flavour; check both, newest first.
const OID_CLAIM_TYPES = [
  'http://schemas.microsoft.com/identity/claims/objectidentifier',
  'oid',
];

interface SwaClaim {
  typ: string;
  val: string;
}
interface SwaClientPrincipal {
  identityProvider?: string;
  userId?: string;
  userRoles?: string[];
  claims?: SwaClaim[];
}

/**
 * Decode `x-ms-client-principal` into the caller's `ownerOid` + app `role`.
 * Returns null when there is no (valid) principal -- i.e. the request is anonymous.
 */
export function getCaller(request: HttpRequest): Caller | null {
  const header = request.headers.get(PRINCIPAL_HEADER);
  if (!header) return null;

  let principal: SwaClientPrincipal;
  try {
    principal = JSON.parse(Buffer.from(header, 'base64').toString('utf8'));
  } catch {
    return null;
  }

  const claims = principal.claims ?? [];
  const ownerOid = claims.find((c) => OID_CLAIM_TYPES.includes(c.typ))?.val ?? principal.userId;
  if (!ownerOid) return null;

  // App roles arrive as `roles` claims. The registration defines exactly listener/uploader/admin
  // (D20), so the value is one of those; an unexpected value simply won't match any role check.
  const role = (claims.find((c) => c.typ === 'roles')?.val ?? null) as Role | null;

  return { ownerOid, role };
}

/**
 * True when the caller is authenticated AND holds one of `allowed`. Use in a handler to
 * gate role-restricted endpoints server-side (library-scoping is layered on top in Epic 4+,
 * never a global grant -- D20).
 */
export function callerHasRole(caller: Caller | null, allowed: readonly Role[]): boolean {
  return caller?.role != null && allowed.includes(caller.role);
}
