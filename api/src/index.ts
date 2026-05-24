// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Placeholder API workspace entry point.
 *
 * Real Azure Static Web Apps managed-functions structure (per D18: Node 22,
 * apiRuntime "node:22"; per D25: connection-string storage auth — not Managed
 * Identity, platform-forced) lands in Sprint 0.3 / Epic 4.
 *
 * This file exists to prove the `@slaylist/shared` workspace import resolves
 * and type-checks (Sprint 0.2 acceptance).
 */

import { DEFAULT_LIBRARY_ID, type Role, type Song } from '@slaylist/shared';

// Compile-time check that the shared types are reachable from /api.
// This binding is intentionally unused at runtime — see `void` below.
const _typeCheck: { libraryId: string; role: Role; songShape: Pick<Song, 'id' | 'state'> } = {
  libraryId: DEFAULT_LIBRARY_ID,
  role: 'uploader',
  songShape: { id: 'placeholder', state: 'processing' },
};

// Silence the "unused" lint while keeping the type-level proof.
void _typeCheck;
