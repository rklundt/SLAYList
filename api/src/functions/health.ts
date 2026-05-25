// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from '@azure/functions';

/**
 * GET /api/health — the trivial health endpoint Sprint 0.3 ships behind the
 * eventual D22 auth gate (gate added in Sprint 2.2).
 *
 * Response minimization per BACKLOG/IS-3: `{status: "ok"}` and a 200. No
 * version info, no build info, no environment name. A health endpoint that
 * leaks internal state is an information-disclosure surface even behind auth.
 *
 * Logging discipline per D32: nothing logged here contains PII. The endpoint
 * doesn't see any identifying data anyway (it's anonymous + content-free).
 *
 * Programming model: Azure Functions v4 programmatic model (`app.http(...)`).
 * Confirmed supported on SWA managed functions per
 * https://learn.microsoft.com/en-us/azure/static-web-apps/add-api (verified
 * 2026-05-24; page last updated 2026-01-23). The Microsoft tutorial uses
 * this exact pattern.
 */

export async function health(
  _request: HttpRequest,
  _context: InvocationContext,
): Promise<HttpResponseInit> {
  return {
    status: 200,
    jsonBody: { status: 'ok' },
  };
}

app.http('health', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'health',
  handler: health,
});
