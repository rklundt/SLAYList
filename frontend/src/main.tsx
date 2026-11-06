// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { PublicClientApplication } from '@azure/msal-browser';
import { MsalProvider } from '@azure/msal-react';
import { App } from './App.js';
import { msalConfig } from './auth/msalConfig.js';
import './App.css';

const rootEl = document.getElementById('root');
if (!rootEl) {
  throw new Error('Root element #root not found in index.html');
}

const msalInstance = new PublicClientApplication(msalConfig);

// MSAL v3+ requires initialize() before any other call; handleRedirectPromise() finishes a
// returning login redirect before React mounts, so the app sees the signed-in account.
void msalInstance
  .initialize()
  .then(() => msalInstance.handleRedirectPromise())
  .then(() => {
    createRoot(rootEl).render(
      <StrictMode>
        <MsalProvider instance={msalInstance}>
          <App />
        </MsalProvider>
      </StrictMode>,
    );
  });
