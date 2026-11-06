// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from '@azure/msal-react';
import { InteractionRequiredAuthError } from '@azure/msal-browser';
import { apiScopes, loginRequest } from './auth/msalConfig.js';

/**
 * Sprint 3.4 — the login gate + role proof.
 *
 * The app now REQUIRES login to show anything beyond the sign-in gate — this retires the
 * Epic-2→Epic-3 "trivial skeleton only" window (the D22 corollary). Anonymous visitors see only the
 * branded gate + the AGPL §13 source-link footer; signed-in users see their resolved role (the
 * end-to-end proof) plus a dev health indicator.
 *
 * IMPORTANT — this client gate is UX, not the security boundary (D22/D43/D44). The real gate is the
 * API: every `/api/*` data request validates the bearer token and returns 401 without a valid,
 * role-bearing one (`api/src/auth.ts`). A determined anonymous client can still fetch the static
 * shell — which holds no family data. Never treat the UI gate as the access control.
 *
 * PII (D32): nothing here logs a name/email; the role string carries no PII. Real mobile-first
 * layout + the player UI are Epic 8.
 */

type HealthState = 'loading' | 'ok' | 'unreachable';

const SOURCE_REPO_URL = 'https://github.com/rklundt/SLAYList';

export function App() {
  return (
    <main className="app">
      <h1>SLAYList</h1>

      <UnauthenticatedTemplate>
        <SignInGate />
      </UnauthenticatedTemplate>
      <AuthenticatedTemplate>
        <SignedInApp />
      </AuthenticatedTemplate>

      <footer className="footer">
        <a href={SOURCE_REPO_URL} rel="noopener noreferrer">
          Source code (AGPL-3.0-or-later)
        </a>
      </footer>
    </main>
  );
}

/** Anonymous view: the gate. Signing in is the only available action. */
function SignInGate() {
  const { instance } = useMsal();
  return (
    <section className="auth">
      <p>Private family music library. Please sign in to continue.</p>
      <button
        type="button"
        onClick={() => void instance.loginRedirect({ ...loginRequest, prompt: 'select_account' })}
      >
        Sign in
      </button>
    </section>
  );
}

/** Signed-in view: the role proof (the end-to-end chain) + a dev health indicator + sign out. */
function SignedInApp() {
  const { instance } = useMsal();
  const role = useRole();
  const health = useHealth();

  // 'loading' | 'error' | 'none' are UI states, not real roles (roles are listener/uploader/admin).
  const isRealRole = role !== 'loading' && role !== 'error' && role !== 'none';

  return (
    <section className="auth">
      {role === 'loading' && <p>Signed in. Checking your role…</p>}
      {role === 'error' && <p>Signed in, but we couldn’t load your role just now. Try refreshing the page.</p>}
      {role === 'none' && (
        <p>Signed in — but your account doesn’t have a role yet. Ask an admin to grant you access.</p>
      )}
      {isRealRole && (
        <p>
          Signed in. Your role: <span className="role">{role}</span>
        </p>
      )}

      <p>
        API: <span className={`status status-${health}`}>{healthLabel(health)}</span>
      </p>

      <button type="button" onClick={() => void instance.logoutRedirect()}>
        Sign out
      </button>
    </section>
  );
}

/**
 * Acquire an access token for the API scope and read GET /api/me to resolve the caller's role.
 * Returns the role string, or a UI sentinel ('loading' | 'error' | 'none').
 */
function useRole(): string {
  const { instance, accounts } = useMsal();
  const [role, setRole] = useState<string>('loading');

  useEffect(() => {
    let cancelled = false;
    const account = accounts[0];
    if (!account) return;
    (async () => {
      try {
        const result = await instance.acquireTokenSilent({ scopes: apiScopes, account });
        // Custom header, NOT Authorization: Azure Static Web Apps overwrites `Authorization` with
        // its own internal platform token before the request reaches the managed Functions API, so
        // the user's bearer token must ride in a header SWA forwards untouched (D44).
        const res = await fetch('/api/me', {
          headers: { 'X-SLAYLIST-Authorization': `Bearer ${result.accessToken}` },
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

  return role;
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
