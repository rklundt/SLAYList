// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, it, expect } from 'vitest';
import type { HttpRequest } from '@azure/functions';
import { getCaller, callerHasRole } from './auth.js';

/** Build a minimal HttpRequest with the SWA client-principal header (base64 JSON), or none. */
function reqWithPrincipal(principal: unknown): HttpRequest {
  const header = principal == null ? null : Buffer.from(JSON.stringify(principal)).toString('base64');
  return {
    headers: { get: (k: string) => (k.toLowerCase() === 'x-ms-client-principal' ? header : null) },
  } as unknown as HttpRequest;
}

describe('getCaller', () => {
  it('returns null when there is no principal (anonymous)', () => {
    expect(getCaller(reqWithPrincipal(null))).toBeNull();
  });

  it('reads ownerOid from the oid claim and role from the roles claim', () => {
    const caller = getCaller(
      reqWithPrincipal({
        userId: 'fallback-id',
        claims: [
          { typ: 'http://schemas.microsoft.com/identity/claims/objectidentifier', val: 'oid-123' },
          { typ: 'roles', val: 'uploader' },
        ],
      }),
    );
    expect(caller).toEqual({ ownerOid: 'oid-123', role: 'uploader' });
  });

  it('falls back to userId for the oid, and role is null when no roles claim', () => {
    expect(getCaller(reqWithPrincipal({ userId: 'uid-9', claims: [] }))).toEqual({
      ownerOid: 'uid-9',
      role: null,
    });
  });

  it('returns null on a malformed (non-JSON) header', () => {
    const req = { headers: { get: () => 'not valid base64 json !!' } } as unknown as HttpRequest;
    expect(getCaller(req)).toBeNull();
  });
});

describe('callerHasRole', () => {
  it('is true only for an authenticated caller holding an allowed role', () => {
    expect(callerHasRole({ ownerOid: 'x', role: 'admin' }, ['admin'])).toBe(true);
    expect(callerHasRole({ ownerOid: 'x', role: 'listener' }, ['admin'])).toBe(false);
    expect(callerHasRole({ ownerOid: 'x', role: null }, ['admin'])).toBe(false);
    expect(callerHasRole(null, ['admin'])).toBe(false);
  });
});
