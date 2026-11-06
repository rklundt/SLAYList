// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen, waitFor } from '@testing-library/react';

/**
 * Component tests for the Sprint 3.4 login gate + role proof.
 *
 * Responsibilities proved here:
 *   1. Render the SLAYList heading + the AGPL §13 source-link footer (D15 — visible even on the gate).
 *   2. Signed out -> ONLY the sign-in gate; app content (role + health) is gated away.
 *   3. Signed in -> resolve the role via /api/me (the end-to-end proof) + show the health indicator.
 *   4. The /api/me call uses the SWA-safe custom header, not Authorization (D44).
 *
 * `@azure/msal-react` is mocked so we drive the auth state directly (no MsalProvider/network).
 * Real mobile-first layout is Epic 8.
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

/** Route fetch by URL so /api/health and /api/me can be stubbed together. Returns the mock. */
function stubFetch(routes: Record<string, { ok: boolean; status?: number; body: unknown }>) {
  const mock = vi.fn((input: string, _init?: RequestInit) => {
    const url = String(input);
    const key = Object.keys(routes).find((k) => url.includes(k));
    const r = key ? routes[key]! : { ok: false, status: 404, body: {} };
    return Promise.resolve({ ok: r.ok, status: r.status ?? (r.ok ? 200 : 500), json: async () => r.body });
  });
  vi.stubGlobal('fetch', mock);
  return mock;
}

beforeEach(() => {
  h.state.authed = false;
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('App — login gate + role proof (Sprint 3.4)', () => {
  it('renders the SLAYList heading', () => {
    stubFetch({});
    render(<App />);
    expect(screen.getByRole('heading', { name: /SLAYList/i })).toBeTruthy();
  });

  it('renders the AGPL §13 source-link footer on the gate (D15 — visible even when signed out)', () => {
    stubFetch({});
    render(<App />);
    const link = screen.getByRole('link', { name: /Source code \(AGPL-3\.0-or-later\)/i });
    expect(link.getAttribute('href')).toBe('https://github.com/rklundt/SLAYList');
  });

  it('signed out: shows ONLY the sign-in gate — no role, no health, no sign-out', () => {
    // Even with /api/* stubbed, the gate must not render app content.
    stubFetch({
      '/api/health': { ok: true, body: { status: 'ok' } },
      '/api/me': { ok: true, body: { role: 'uploader' } },
    });
    render(<App />);
    expect(screen.getByRole('button', { name: /sign in/i })).toBeTruthy();
    expect(screen.getByText(/please sign in/i)).toBeTruthy();
    // App content is gated away:
    expect(screen.queryByRole('button', { name: /sign out/i })).toBeNull();
    expect(screen.queryByText(/your role/i)).toBeNull();
    expect(screen.queryByText('ok')).toBeNull(); // no health indicator when signed out
  });

  it('signed in: shows the resolved role (end-to-end proof) + the health indicator', async () => {
    h.state.authed = true;
    stubFetch({
      '/api/health': { ok: true, body: { status: 'ok' } },
      '/api/me': { ok: true, body: { role: 'uploader' } },
    });
    render(<App />);
    await waitFor(() => expect(screen.getByText('uploader')).toBeTruthy());
    await waitFor(() => expect(screen.getByText('ok')).toBeTruthy());
    expect(h.instance.acquireTokenSilent).toHaveBeenCalled();
  });

  it('signed in: calls /api/me with the SWA-safe custom header, NOT Authorization (D44)', async () => {
    h.state.authed = true;
    const fetchMock = stubFetch({
      '/api/health': { ok: true, body: { status: 'ok' } },
      '/api/me': { ok: true, body: { role: 'admin' } },
    });
    render(<App />);
    await waitFor(() => expect(screen.getByText('admin')).toBeTruthy());

    const meCall = fetchMock.mock.calls.find((c) => String(c[0]).includes('/api/me'));
    expect(meCall).toBeTruthy();
    const headers = (meCall![1] as RequestInit).headers as Record<string, string>;
    expect(headers['X-SLAYLIST-Authorization']).toMatch(/^Bearer /);
    expect(headers['Authorization']).toBeUndefined();
  });
});
