// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

/// <reference types="vitest" />
import { defineConfig } from 'vitest/config';

// Vitest config for the SLAYList API (Azure Functions) workspace.
//
// The `include` is scoped to `src` on purpose — mirroring frontend/vite.config.ts.
// Without this scope, Vitest 4's default test discovery also picks up the COMPILED
// test artifacts under `dist` (tsc emits the source test files to `dist` as `.js`),
// which double-runs the suite and, worse, runs generated build output as if it were
// a source test. Vitest 3's defaults excluded `dist`; Vitest 4 changed that, which is
// why this file became necessary at the 3 -> 4 bump. An `include` allowlist scoped to
// `src` ignores `dist` regardless of what the build leaves there. Tests run in the default
// `node` environment — these are pure handler tests, no DOM.
export default defineConfig({
  test: {
    environment: 'node',
    globals: false,
    include: ['src/**/*.test.ts'],
  },
});
