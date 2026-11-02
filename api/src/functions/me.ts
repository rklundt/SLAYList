// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from '@azure/functions';
import { getCaller } from '../auth.js';

/**
 * GET /api/me -- returns the signed-in caller's role.
 *
 * With client-side MSAL (Sprint 3.3) there is no SWA edge auth: this handler validates the
 * `Authorization: Bearer` token itself via getCaller and returns 401 on a missing/invalid
 * token (InfoSec: authorize server-side). It's the endpoint Sprint 3.4's "your role is X"
 * proof reads.
 *
 * Response is intentionally minimal: just the role (no name, no email). Logging per D32:
 * `ownerOid` only -- never a display name.
 */
export async function me(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  const caller = await getCaller(request);
  if (!caller) {
    return { status: 401, jsonBody: { error: 'not authenticated' } };
  }
  context.log(`GET /api/me ownerOid=${caller.ownerOid} role=${caller.role ?? 'none'}`);
  return { status: 200, jsonBody: { role: caller.role } };
}

app.http('me', {
  methods: ['GET'],
  authLevel: 'anonymous', // no SWA edge auth (MSAL); getCaller validates the bearer token in code
  route: 'me',
  handler: me,
});
