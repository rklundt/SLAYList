// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

// TEMPORARY Sprint 3.3 diagnostic — DELETE before /wrap-sprint. Surfaces why a valid bearer
// token is rejected by the API (header forwarding? runtime env? jose signature?). Mirrors
// auth.ts's config exactly but reports instead of swallowing. No secret is emitted (clientId +
// tenantId are public; only the token's own aud/iss + jose's error string are echoed back).
import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from '@azure/functions';
import { createRemoteJWKSet, jwtVerify } from 'jose';

const TENANT_ID = process.env.AAD_TENANT_ID ?? '';
const CLIENT_ID = process.env.AAD_CLIENT_ID ?? '';
const ISSUER = `https://login.microsoftonline.com/${TENANT_ID}/v2.0`;
const JWKS_URI = `https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys`;
const AUDIENCE = [CLIENT_ID, `api://${CLIENT_ID}`];
const jwks = TENANT_ID ? createRemoteJWKSet(new URL(JWKS_URI)) : null;

export async function authdebug(
  request: HttpRequest,
  _context: InvocationContext,
): Promise<HttpResponseInit> {
  const authHeader = request.headers.get('authorization');
  const customHeader = request.headers.get('x-slaylist-authorization');
  const picked = customHeader ?? authHeader;
  const m = picked ? /^Bearer\s+(.+)$/i.exec(picked.trim()) : null;
  const token = m ? m[1] : null;
  const out: Record<string, unknown> = {
    authHeaderPresent: authHeader != null,
    authHeaderSample: authHeader ? authHeader.slice(0, 10) : null,
    customHeaderPresent: customHeader != null,
    customHeaderSample: customHeader ? customHeader.slice(0, 10) : null,
    tenantSet: Boolean(TENANT_ID),
    clientSet: Boolean(CLIENT_ID),
    jwksReady: Boolean(jwks),
    expectedIssuer: ISSUER,
    expectedAudience: AUDIENCE,
    tokenPresent: Boolean(token),
  };
  if (token) {
    const parts = token.split('.');
    try {
      const p = JSON.parse(Buffer.from(parts[1] ?? '', 'base64url').toString()) as Record<string, unknown>;
      out.tokenAud = p.aud;
      out.tokenIss = p.iss;
      out.tokenHasRoles = Array.isArray(p.roles);
    } catch (e) {
      out.decodeError = String(e);
    }
    if (jwks) {
      try {
        await jwtVerify(token, jwks, { issuer: ISSUER, audience: AUDIENCE });
        out.verify = 'OK';
      } catch (e) {
        out.verify = 'FAIL';
        out.verifyError = (e as Error).message;
      }
    }
  }
  return { status: 200, jsonBody: out };
}

app.http('authdebug', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'authdebug',
  handler: authdebug,
});
