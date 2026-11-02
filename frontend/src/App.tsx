// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from '@azure/msal-react';
import { InteractionRequiredAuthError } from '@azure/msal-browser';
import { apiScopes, loginRequest } from './auth/msalConfig.js';

/**
 * Sprint 3.3 — the walking-skeleton UI, now auth-aware (client-side MSAL).
 *
 * Jobs:
 *   1. Render the app heading + the AGPL §13 source-link footer (D15 — every UI from 0.3 on
 *      inherits this).
 *   2. Round-trip GET /api/health (anonymous) so the frontend ↔ API wire stays visibly verified.
 *   3. When signed out, offer "Sign in" (MSAL redirect). When signed in, acquire an access token
 *      for the API scope and read GET /api/me to display the caller's role (Sprint 3.4 polishes
 *      this into the real gate + role display).
 *
 * Logging discipline (D32): nothing logged here is PII — the role lookup carries no name/email,
 * and the health check has no body. Real mobile-first layout is Epic 8.
 */

type HealthState = 'loading' | 'ok' | 'unreachable';

const SOURCE_REPO_URL = 'https://github.com/rklundt/SLAYList';

export function App() {
  const health = useHealth();

  return (
    <main className="app">
      <h1>SLAYList — it works</h1>
      <p>
        API: <span className={`status status-${health}`}>{healthLabel(health)}</span>
      </p>

      <UnauthenticatedTemplate>
        <SignIn />
      </UnauthenticatedTemplate>
      <AuthenticatedTemplate>
        <RoleReadout />
      </AuthenticatedTemplate>

      <footer className="footer">
        <a href={SOURCE_REPO_URL} rel="noopener noreferrer">
          Source code (AGPL-3.0-or-later)
        </a>
      </footer>
    </main>
  );
}

function SignIn() {
  const { instance } = useMsal();
  return (
    <section className="auth">
      <p>Private family library — please sign in.</p>
      <button type="button" onClick={() => void instance.loginRedirect(loginRequest)}>
        Sign in
      </button>
    </section>
  );
}

function RoleReadout() {
  const { instance, accounts } = useMsal();
  const [role, setRole] = useState<string>('loading');

  useEffect(() => {
    let cancelled = false;
    const account = accounts[0];
    if (!account) return;
    (async () => {
      try {
        const result = await instance.acquireTokenSilent({ scopes: apiScopes, account });
        const res = await fetch('/api/me', {
          headers: { Authorization: `Bearer ${result.accessToken}` },
        });
        if (!res.ok) {
          throw new Error(`HTTP ${res.status}`);
        }
        const body = (await res.json()) as { role?: string | null };
        if (!cancelled) {
          setRole(body.role ?? 'none');
        }
      } catch (err) {
        // A silent-token failure that needs interaction -> fall back to a redirect.
        if (err instanceof InteractionRequiredAuthError) {
          void instance.acquireTokenRedirect({ scopes: apiScopes });
          return;
        }
        if (!cancelled) {
          setRole('error');
          // D32: nothing here is PII — the role lookup carries no name/email.
          console.error('Role lookup failed', err);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [instance, accounts]);

  return (
    <section className="auth">
      <p>
        Signed in. Your role:{' '}
        <span className="role">{role === 'loading' ? 'checking…' : role}</span>
      </p>
      <button type="button" onClick={() => void instance.logoutRedirect()}>
        Sign out
      </button>
    </section>
  );
}

function useHealth(): HealthState {
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
      } catch (err) {
        if (!cancelled) {
          setHealth('unreachable');
          console.error('Health check fetch failed', err);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);
  return health;
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
