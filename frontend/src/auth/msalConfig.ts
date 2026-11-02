// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * MSAL (client-side auth) configuration for the SLAYList SPA (Sprint 3.3).
 *
 * The SPA is a PUBLIC client: it signs the user in with the authorization-code + PKCE flow
 * against the custom Entra app (`slaylist-auth-dev`) -- no client secret lives in the browser.
 * It then requests an ACCESS TOKEN for this same app's exposed API scope and sends it to the
 * API as a bearer token; the API validates it (see api/src/auth.ts). Family restriction
 * (appRoleAssignmentRequired) and the role claim are enforced by Entra + the API, not here.
 *
 * clientId + tenant come from build-time env (vite-env.d.ts) -- public values, injected at
 * build, never committed (D17). authority is single-tenant (D2).
 */

import type { Configuration } from '@azure/msal-browser';

const clientId = import.meta.env.VITE_AAD_CLIENT_ID;
const tenantId = import.meta.env.VITE_AAD_TENANT_ID;

export const msalConfig: Configuration = {
  auth: {
    clientId,
    authority: `https://login.microsoftonline.com/${tenantId}`,
    // The SPA returns here after the login redirect; must match an SPA redirect URI on the
    // app registration (the deployed SWA origin, or http://localhost:5193 for `pnpm dev`).
    redirectUri: window.location.origin,
    postLogoutRedirectUri: window.location.origin,
  },
  cache: {
    // Per-tab session storage: tokens are not persisted to localStorage across browser sessions.
    cacheLocation: 'sessionStorage',
  },
};

/** The access-token scope for our own API, exposed as `api://<clientId>/access_as_user`. */
export const apiScopes = [`api://${clientId}/access_as_user`];

/** Login request: ask for the API scope up front so the first token already works for /api/*. */
export const loginRequest = { scopes: apiScopes };
