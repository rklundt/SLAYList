// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, it, expect } from 'vitest';
import type { HttpRequest, InvocationContext } from '@azure/functions';
import { health } from './health.js';

/**
 * Unit test for the /api/health handler.
 *
 * Verifies the response shape contract documented in D32 + BACKLOG IS-3:
 * `{status: "ok"}` and a 200 status code, nothing more. This shape MUST
 * stay tight — adding version/build/environment info would re-introduce
 * the information-disclosure surface that response-minimization closes.
 *
 * Tests the handler function as a pure function. The `app.http(...)`
 * registration is a side-effect of importing the module (`./health.js`)
 * but doesn't run a real function host in this unit context.
 */

describe('GET /api/health handler', () => {
  it('returns 200 with exactly {status: "ok"} — response-minimization (D32 / IS-3)', async () => {
    const request = {} as HttpRequest;
    const context = {} as InvocationContext;

    const result = await health(request, context);

    expect(result.status).toBe(200);
    expect(result.jsonBody).toEqual({ status: 'ok' });
  });

  it('response body has no version/build/environment leak (response-minimization invariant)', async () => {
    const result = await health({} as HttpRequest, {} as InvocationContext);
    const body = result.jsonBody as Record<string, unknown>;

    // The forbidden fields a future "helpful" change might tempt — fail the test
    // if any of these appear, to keep the response surface minimal per IS-3.
    expect(body).not.toHaveProperty('version');
    expect(body).not.toHaveProperty('build');
    expect(body).not.toHaveProperty('environment');
    expect(body).not.toHaveProperty('env');
    expect(body).not.toHaveProperty('commit');
    expect(body).not.toHaveProperty('sha');
    expect(body).not.toHaveProperty('uptime');
    expect(Object.keys(body)).toEqual(['status']);
  });
});
