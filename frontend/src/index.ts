// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Placeholder frontend workspace entry point.
 *
 * Real Vite + React PWA shell + the "SLAYList — it works" page + the AGPL § 13
 * source-link footer pointing at https://github.com/rklundt/SLAYList land in
 * Sprint 0.3. This file exists to prove the `@slaylist/shared` workspace
 * import resolves and type-checks (Sprint 0.2 acceptance).
 */

import { DEFAULT_LIBRARY_ID, ROLES, type Song } from '@slaylist/shared';

// Compile-time check that the shared types are reachable from /frontend.
const _typeCheck: { libraryId: string; rolesCount: number; songShape: Pick<Song, 'id' | 'title' | 'state'> } = {
  libraryId: DEFAULT_LIBRARY_ID,
  rolesCount: ROLES.length,
  songShape: { id: 'placeholder', title: 'placeholder', state: 'ready' },
};

void _typeCheck;
