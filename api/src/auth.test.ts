// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, it, expect, beforeAll } from 'vitest';
import { SignJWT, generateKeyPair } from 'jose';
import type { HttpRequest } from '@azure/functions';
import { verifyBearer, mapClaims, extractBearer, callerHasRole } from './auth.js';

// A fixed issuer/audience for the tests -- verifyBearer takes them explicitly, so no env
// or network (JWKS) is involved; we sign with a local key pair and verify with its public key.
const ISSUER = 'https://login.microsoftonline.com/test-tenant/v2.0';
const AUDIENCE = 'test-client-id';
const nowSec = () => Math.floor(Date.now() / 1000);

type KeyPair = Awaited<ReturnType<typeof generateKeyPair>>;
let keys: KeyPair; // the "real" Entra key
let otherKeys: KeyPair; // a different key, for the bad-signature case

beforeAll(async () => {
  keys = await generateKeyPair('RS256');
  otherKeys = await generateKeyPair('RS256');
});

/** Sign a JWT with the (by default valid) issuer/audience/exp, overridable per-case. */
function sign(
  claims: Record<string, unknown>,
  opts: { issuer?: string; audience?: string; exp?: number; key?: KeyPair['privateKey'] } = {},
): Promise<string> {
  return new SignJWT(claims)
    .setProtectedHeader({ alg: 'RS256' })
    .setIssuer(opts.issuer ?? ISSUER)
    .setAudience(opts.audience ?? AUDIENCE)
    .setIssuedAt()
    .setExpirationTime(opts.exp ?? nowSec() + 300)
    .sign(opts.key ?? keys.privateKey);
}

const verify = (token: string) => verifyBearer(token, keys.publicKey, { issuer: ISSUER, audience: AUDIENCE });

describe('verifyBearer', () => {
  it('accepts a valid token and maps oid + role', async () => {
    const token = await sign({ oid: 'oid-123', roles: ['uploader'] });
    expect(await verify(token)).toEqual({ ownerOid: 'oid-123', role: 'uploader' });
  });

  it('role is null when there is no roles claim', async () => {
    const token = await sign({ oid: 'oid-9' });
    expect(await verify(token)).toEqual({ ownerOid: 'oid-9', role: null });
  });

  it('rejects a token signed by a different key (bad signature)', async () => {
    const token = await sign({ oid: 'oid-1', roles: ['admin'] }, { key: otherKeys.privateKey });
    expect(await verify(token)).toBeNull();
  });

  it('rejects a wrong audience', async () => {
    const token = await sign({ oid: 'oid-1', roles: ['admin'] }, { audience: 'some-other-app' });
    expect(await verify(token)).toBeNull();
  });

  it('rejects a wrong issuer', async () => {
    const token = await sign({ oid: 'oid-1', roles: ['admin'] }, { issuer: 'https://evil.example/v2.0' });
    expect(await verify(token)).toBeNull();
  });

  it('rejects an expired token', async () => {
    const token = await sign({ oid: 'oid-1', roles: ['admin'] }, { exp: nowSec() - 60 });
    expect(await verify(token)).toBeNull();
  });

  it('rejects an otherwise-valid token that carries no oid', async () => {
    const token = await sign({ roles: ['admin'] });
    expect(await verify(token)).toBeNull();
  });
});

describe('extractBearer', () => {
  // Case-insensitive header bag, mirroring Azure Functions' Headers.get.
  const req = (headers: Record<string, string>): HttpRequest =>
    ({ headers: { get: (k: string) => headers[k.toLowerCase()] ?? null } }) as unknown as HttpRequest;
  const CUSTOM = 'x-slaylist-authorization';

  it('reads the token from the SLAYList custom header — how the SPA sends it (D44)', () =>
    expect(extractBearer(req({ [CUSTOM]: 'Bearer abc.def.ghi' }))).toBe('abc.def.ghi'));
  it('prefers the custom header over Authorization (SWA overwrites Authorization — D44)', () =>
    expect(extractBearer(req({ [CUSTOM]: 'Bearer good', authorization: 'Bearer platform-token' }))).toBe('good'));
  it('falls back to Authorization for local dev when no custom header is present', () =>
    expect(extractBearer(req({ authorization: 'Bearer abc.def.ghi' }))).toBe('abc.def.ghi'));
  it('is case-insensitive on the scheme', () => expect(extractBearer(req({ [CUSTOM]: 'bearer xyz' }))).toBe('xyz'));
  it('returns null without any auth header', () => expect(extractBearer(req({}))).toBeNull());
  it('returns null on a non-Bearer header', () => expect(extractBearer(req({ [CUSTOM]: 'Basic abc' }))).toBeNull());
});

describe('mapClaims', () => {
  it('takes the first role from the roles array', () =>
    expect(mapClaims({ oid: 'x', roles: ['listener', 'admin'] })).toEqual({ ownerOid: 'x', role: 'listener' }));
  it('null role when the roles array is empty', () =>
    expect(mapClaims({ oid: 'x', roles: [] })).toEqual({ ownerOid: 'x', role: null }));
  it('null when oid is missing', () => expect(mapClaims({ roles: ['admin'] })).toBeNull());
});

describe('callerHasRole', () => {
  it('is true only for an authenticated caller holding an allowed role', () => {
    expect(callerHasRole({ ownerOid: 'x', role: 'admin' }, ['admin'])).toBe(true);
    expect(callerHasRole({ ownerOid: 'x', role: 'listener' }, ['admin'])).toBe(false);
    expect(callerHasRole({ ownerOid: 'x', role: null }, ['admin'])).toBe(false);
    expect(callerHasRole(null, ['admin'])).toBe(false);
  });
});
