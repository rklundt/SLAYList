// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Server-side auth helper for the SLAYList API (Epic 3).
 *
 * AUTH MODEL (Sprint 3.3 -- client-side MSAL): the React SPA signs the user in with MSAL
 * against the custom Entra app (`slaylist-auth-dev`) and calls `/api/*` with an
 * `Authorization: Bearer <access-token>` header. This module validates that JWT itself --
 * signature (Entra JWKS), issuer, audience, expiry -- then maps the `oid` + `roles` claims
 * to the caller's stable id + app role. There is NO SWA edge auth on the Free SKU (custom
 * SWA auth needs Standard -- D26), so every data endpoint MUST call getCaller and reject on
 * null. Authorization is enforced server-side, never trusted from the UI (InfoSec rule).
 *
 * MIGRATION SEAM (keep intact): everything downstream depends only on
 * `getCaller(request) -> Caller` + `callerHasRole`, never on HOW the identity was derived.
 * If the app later moves to SWA built-in auth on Standard, ONLY getCaller's body changes:
 * swap bearer-JWT validation for decoding the SWA-injected `x-ms-client-principal` header
 * (base64 JSON -> read the `oid`-type claim + the `roles` claim). Roles, assignments, and
 * every consumer stay identical. (See DECISIONS: MSAL-now / built-in-later.)
 *
 * `Role` is a TYPE-ONLY import (erased from the compiled JS) so the shared package stays the
 * single source of truth without becoming a runtime dependency of the deployed function.
 *
 * PII discipline (D32): the only identity field used for authz/logging is `ownerOid` (the
 * opaque, stable Entra object id, D21). Never read or log displayName / email.
 */

import type { HttpRequest } from '@azure/functions';
import type { Role } from '@slaylist/shared';
import { createRemoteJWKSet, jwtVerify, type JWTPayload, type JWTVerifyGetKey } from 'jose';

export interface Caller {
  /** Stable Entra object id (`oid`). The ONLY identity field used for authz + logs (D21/D32). */
  ownerOid: string;
  /** The caller's app role from the token's `roles` claim, or null if none is present. */
  role: Role | null;
}

// --- Config from app settings (wired by the deploy workflow). Single-tenant (D2). ---
const TENANT_ID = process.env.AAD_TENANT_ID ?? '';
const CLIENT_ID = process.env.AAD_CLIENT_ID ?? '';
// Entra v2 issuer + JWKS endpoint for this tenant.
const ISSUER = `https://login.microsoftonline.com/${TENANT_ID}/v2.0`;
const JWKS_URI = `https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys`;
// The access token's audience is this app. Entra emits either the bare client id or the
// `api://<clientId>` App ID URI depending on token version, so accept both.
const AUDIENCE = [CLIENT_ID, `api://${CLIENT_ID}`];

// Remote JWKS resolver, created once (jose caches keys + rate-limits refetches internally).
// Null only in a misconfigured env (no tenant set) -- getCaller then rejects everything.
const remoteJwks: JWTVerifyGetKey | null = TENANT_ID ? createRemoteJWKSet(new URL(JWKS_URI)) : null;

/** Pull the raw bearer token from the Authorization header, or null if absent/malformed. */
export function extractBearer(request: HttpRequest): string | null {
  const header = request.headers.get('authorization');
  if (!header) return null;
  const m = /^Bearer\s+(.+)$/i.exec(header.trim());
  return m ? (m[1] ?? null) : null;
}

/** Map a verified JWT payload to a Caller. Returns null if the required `oid` is missing. */
export function mapClaims(payload: JWTPayload): Caller | null {
  const ownerOid = typeof payload.oid === 'string' ? payload.oid : undefined;
  if (!ownerOid) return null;
  // App roles arrive as a `roles` string array. Our registration assigns exactly one of
  // listener/uploader/admin (D20); take the first. An unexpected value simply won't match
  // any callerHasRole check.
  const roles = Array.isArray(payload.roles) ? payload.roles : [];
  const role = (typeof roles[0] === 'string' ? roles[0] : null) as Role | null;
  return { ownerOid, role };
}

/**
 * Verify a bearer token against the given key resolver and map it to a Caller. Exposed
 * (not inlined) so unit tests can pass a local key + issuer/audience without touching the
 * network. Any verification failure yields null (treat the request as anonymous).
 */
export async function verifyBearer(
  token: string,
  keys: Parameters<typeof jwtVerify>[1],
  opts: { issuer: string; audience: string | string[] },
): Promise<Caller | null> {
  try {
    const { payload } = await jwtVerify(token, keys, opts);
    return mapClaims(payload);
  } catch {
    return null;
  }
}

/**
 * Decode + fully validate the request's bearer token into the caller's `ownerOid` + app
 * `role`. Returns null when there is no token or it fails validation -- i.e. anonymous.
 * Async because signature/JWKS verification is async.
 */
export async function getCaller(request: HttpRequest): Promise<Caller | null> {
  const token = extractBearer(request);
  if (!token || !remoteJwks) return null;
  return verifyBearer(token, remoteJwks, { issuer: ISSUER, audience: AUDIENCE });
}

/**
 * True when the caller is authenticated AND holds one of `allowed`. Use in a handler to
 * gate role-restricted endpoints server-side (library-scoping is layered on top in Epic 4+,
 * never a global grant -- D20).
 */
export function callerHasRole(caller: Caller | null, allowed: readonly Role[]): boolean {
  return caller?.role != null && allowed.includes(caller.role);
}
