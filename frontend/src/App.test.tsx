// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen, waitFor } from '@testing-library/react';

/**
 * Component tests for the Sprint 3.3 auth-aware skeleton UI.
 *
 * Responsibilities proved here:
 *   1. Render the heading + the AGPL §13 source-link footer (D15 guardrail).
 *   2. Round-trip /api/health and display the result (frontend ↔ API wire).
 *   3. Signed out -> a "Sign in" control; signed in -> read /api/me and show the role.
 *
 * `@azure/msal-react` is mocked so we drive the auth state directly (no MsalProvider/network).
 * Real mobile-first layout + the polished gate are Epic 8 / Sprint 3.4.
 */

const h = vi.hoisted(() => ({
  state: { authed: false },
  instance: {
    loginRedirect: vi.fn(),
    logoutRedirect: vi.fn(),
    acquireTokenSilent: vi.fn().mockResolvedValue({ accessToken: 'test-token' }),
  },
}));

vi.mock('@azure/msal-react', () => ({
  useMsal: () => ({
    instance: h.instance,
    accounts: h.state.authed ? [{ homeAccountId: 'acct-1', username: 'x' }] : [],
  }),
  AuthenticatedTemplate: ({ children }: { children: React.ReactNode }) =>
    h.state.authed ? children : null,
  UnauthenticatedTemplate: ({ children }: { children: React.ReactNode }) =>
    h.state.authed ? null : children,
}));

// Imported AFTER the mock is declared.
const { App } = await import('./App.js');

/** Route fetch by URL so /api/health and /api/me can be stubbed together. */
function stubFetch(routes: Record<string, { ok: boolean; status?: number; body: unknown }>) {
  vi.stubGlobal(
    'fetch',
    vi.fn((input: string) => {
      const url = String(input);
      const key = Object.keys(routes).find((k) => url.includes(k));
      const r = key ? routes[key]! : { ok: false, status: 404, body: {} };
      return Promise.resolve({ ok: r.ok, status: r.status ?? (r.ok ? 200 : 500), json: async () => r.body });
    }),
  );
}

beforeEach(() => {
  h.state.authed = false;
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('App — auth-aware skeleton (Sprint 3.3)', () => {
  it('renders the heading', () => {
    stubFetch({ '/api/health': { ok: true, body: { status: 'ok' } } });
    render(<App />);
    expect(screen.getByRole('heading', { name: /SLAYList/i })).toBeTruthy();
  });

  it('renders the AGPL §13 source-link footer pointing at the public repo (D15 guardrail)', () => {
    stubFetch({ '/api/health': { ok: true, body: { status: 'ok' } } });
    render(<App />);
    const link = screen.getByRole('link', { name: /Source code \(AGPL-3\.0-or-later\)/i });
    expect(link.getAttribute('href')).toBe('https://github.com/rklundt/SLAYList');
  });

  it('shows API: ok when /api/health responds 200 with {status: "ok"}', async () => {
    stubFetch({ '/api/health': { ok: true, body: { status: 'ok' } } });
    render(<App />);
    await waitFor(() => expect(screen.getByText('ok')).toBeTruthy());
  });

  it('offers a "Sign in" control when signed out', () => {
    stubFetch({ '/api/health': { ok: true, body: { status: 'ok' } } });
    render(<App />);
    expect(screen.getByRole('button', { name: /sign in/i })).toBeTruthy();
  });

  it('reads /api/me and shows the role when signed in', async () => {
    h.state.authed = true;
    stubFetch({
      '/api/health': { ok: true, body: { status: 'ok' } },
      '/api/me': { ok: true, body: { role: 'uploader' } },
    });
    render(<App />);
    await waitFor(() => expect(screen.getByText('uploader')).toBeTruthy());
    // The bearer token from acquireTokenSilent was used.
    expect(h.instance.acquireTokenSilent).toHaveBeenCalled();
  });
});
