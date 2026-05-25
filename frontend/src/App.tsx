// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';

/**
 * Sprint 0.3 — the trivial "walking skeleton" UI.
 *
 * Three jobs, deliberately:
 *   1. Render "SLAYList — it works" so the human can see the frontend is alive.
 *   2. Call `GET /api/health` and display the round-trip result so the frontend
 *      ↔ API wire is visibly verified.
 *   3. Render the AGPL § 13 source-link footer (per the D15 guardrail in
 *      CLAUDE.md — every UI from 0.3 onward inherits this).
 *
 * Logging discipline (D32): nothing logged here contains PII (`ownerOid` /
 * `ownerDisplayName` / song titles don't exist yet — this is the skeleton).
 * The catch-block log is generic — no request body, no user-identifying data.
 *
 * Styling discipline (per Sprint 0.3 plan): minimal functional CSS only —
 * legible text + the green-OK / red-failure status cue (which earns its place
 * by serving the page's one job, proving the round-trip visibly). No layout,
 * branding, or fonts here. Epic 8 owns the real mobile-first UI.
 */

type HealthState = 'loading' | 'ok' | 'unreachable';

const SOURCE_REPO_URL = 'https://github.com/rklundt/SLAYList';

export function App() {
  const [health, setHealth] = useState<HealthState>('loading');

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch('/api/health');
        if (!res.ok) {
          throw new Error(`HTTP ${res.status}`);
        }
        const body = (await res.json()) as { status?: string };
        if (!cancelled) {
          setHealth(body.status === 'ok' ? 'ok' : 'unreachable');
        }
      } catch {
        if (!cancelled) {
          setHealth('unreachable');
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <main className="app">
      <h1>SLAYList — it works</h1>
      <p>
        API: <span className={`status status-${health}`}>{healthLabel(health)}</span>
      </p>
      <footer className="footer">
        <a href={SOURCE_REPO_URL} rel="noopener noreferrer">
          Source code (AGPL-3.0-or-later)
        </a>
      </footer>
    </main>
  );
}

function healthLabel(state: HealthState): string {
  switch (state) {
    case 'loading':
      return 'checking…';
    case 'ok':
      return 'ok';
    case 'unreachable':
      return 'unreachable';
  }
}
