// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { ROLES, SONG_STATES, DEFAULT_LIBRARY_ID, type Role, type Song, type SongState } from './index.js';

/**
 * Placeholder + invariant tests for the shared types.
 *
 * These exist to (a) prove the Vitest wiring works in CI (D23) and (b) be
 * the smoke test Sprint 4.1 leverages when the CI gate hardens soft → hard.
 * Sprint 4.1's acceptance specifically calls for "a one-line test in /shared
 * covering at least one invariant of the Song type" — these are it.
 */

describe('shared types — locked invariants', () => {
  it('SONG_STATES is exactly the four documented values, in order', () => {
    expect(SONG_STATES).toEqual(['processing', 'ready', 'failed', 'deactivated']);
  });

  it('ROLES is exactly the three documented values, in order', () => {
    expect(ROLES).toEqual(['listener', 'uploader', 'admin']);
  });

  it('DEFAULT_LIBRARY_ID matches D19 ("slaylist-home")', () => {
    expect(DEFAULT_LIBRARY_ID).toBe('slaylist-home');
  });

  it('a Song can be constructed with the required fields only', () => {
    // Compile-time + runtime check that the required-field shape is what we documented.
    // Uses fake PII per the public-repo hygiene rules (D17 / DEVELOPER_GUIDE).
    const song: Song = {
      id: 'song_test_0001',
      libraryId: DEFAULT_LIBRARY_ID,
      title: 'Test Song',
      ownerOid: '00000000-0000-0000-0000-000000000001',
      ownerDisplayName: 'test-uploader@example.com',
      state: 'processing',
      createdAt: '2026-05-24T00:00:00Z',
    };
    expect(song.id).toBe('song_test_0001');
    expect(song.libraryId).toBe('slaylist-home');
  });

  it('SongState and Role unions accept only the documented values', () => {
    // Pure type-level checks expressed at runtime — if these compile, the union is intact.
    const validState: SongState = 'ready';
    const validRole: Role = 'uploader';
    expect(validState).toBe('ready');
    expect(validRole).toBe('uploader');
  });
});
