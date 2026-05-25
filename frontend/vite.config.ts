// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

/// <reference types="vitest" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

/**
 * Vite config for the SLAYList frontend (Sprint 0.3).
 *
 * Local dev (the `pnpm dev` pattern):
 *   - Vite dev server runs on port 5193 (deliberately non-default to avoid
 *     conflict with other local apps on the default 5173).
 *   - The Azure Functions Core Tools (`func`) runs the API on port 7071.
 *   - Vite proxies `/api/*` to `http://localhost:7071/api/*` so the frontend
 *     can call `/api/health` as if both halves were under one origin —
 *     matching the deployed Azure Static Web Apps routing without putting
 *     SWA CLI in the local-dev loop (SWA CLI's local emulator had pnpm-
 *     resolution issues during Sprint 0.3 verification; using Vite proxy
 *     here keeps local dev reliable. The deploy path is still SWA — its
 *     own routing handles `/api/*` in production. Sprint 2.2 verifies the
 *     SWA build end-to-end.)
 *
 * Build (`pnpm build`):
 *   - Output goes to `dist/`, including `staticwebapp.config.json` from
 *     `public/` (Vite auto-copies the public folder). Sprint 2.2's SWA
 *     deploy consumes `dist/`.
 *
 * Run from the repo root: `pnpm dev` (concurrently runs func + this dev
 * server). Browse `http://localhost:5193`.
 */
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5193,
    strictPort: true,
    proxy: {
      '/api': {
        target: 'http://localhost:7071',
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
  test: {
    // happy-dom over jsdom: faster startup, smaller deps, sufficient for the
    // skeleton we're testing. Reconsider if Sprint 8's real UI needs jsdom
    // features happy-dom lacks.
    environment: 'happy-dom',
    globals: false,
    include: ['src/**/*.test.{ts,tsx}'],
  },
});
