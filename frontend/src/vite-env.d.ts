// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

/// <reference types="vite/client" />

/**
 * Build-time env the frontend reads via `import.meta.env` (Vite inlines `VITE_*`).
 * These are NOT secrets: a client id and tenant id are public in any OAuth SPA bundle.
 * They are kept out of source and injected at build time from GitHub secrets (D17 posture).
 */
interface ImportMetaEnv {
  readonly VITE_AAD_CLIENT_ID: string;
  readonly VITE_AAD_TENANT_ID: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
