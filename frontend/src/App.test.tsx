// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen, waitFor } from '@testing-library/react';
import { App } from './App.js';

/**
 * Component tests for the Sprint 0.3 "walking skeleton" UI.
 *
 * Three things this page is responsible for (per Sprint 0.3 acceptance):
 *   1. Render "SLAYList — it works".
 *   2. Render the AGPL §13 source-link footer (D15 — every UI from 0.3 on
 *      inherits this; without it, the UI ships out of license compliance).
 *   3. Round-trip /api/health and display the result (the visible proof
 *      that frontend ↔ API is wired).
 *
 * Mobile-first / real layout tests belong to Sprint 8 (Epic 8 owns the UI).
 * These tests are the minimum that proves the contract.
 */

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe('App — Sprint 0.3 walking-skeleton UI', () => {
  it('renders the "SLAYList — it works" heading', () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => ({ status: 'ok' }) }));

    render(<App />);

    expect(screen.getByRole('heading', { name: /SLAYList — it works/i })).toBeTruthy();
  });

  it('renders the AGPL §13 source-link footer pointing at the public repo (D15 guardrail)', () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, json: async () => ({ status: 'ok' }) }));

    render(<App />);

    const link = screen.getByRole('link', { name: /Source code \(AGPL-3\.0-or-later\)/i });
    expect(link.getAttribute('href')).toBe('https://github.com/rklundt/SLAYList');
  });

  it('shows API: ok when /api/health responds 200 with {status: "ok"}', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({ ok: true, json: async () => ({ status: 'ok' }) }),
    );

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText('ok')).toBeTruthy();
    });
  });

  it('shows API: unreachable when /api/health rejects', async () => {
    // Silence the console.error the App emits on failure (D32 / Epic 1+ followup
    // is the proper telemetry path; the console.error is dev-only).
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('network error')));

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText('unreachable')).toBeTruthy();
    });
  });

  it('shows API: unreachable when /api/health responds non-2xx', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({ ok: false, status: 500, json: async () => ({}) }),
    );

    render(<App />);

    await waitFor(() => {
      expect(screen.getByText('unreachable')).toBeTruthy();
    });
  });
});
