// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Placeholder transcoder workspace entry point.
 *
 * Real ffmpeg transcode logic + Dockerfile + the D32 stderr/filename hygiene
 * (use songId-based local filenames during transcode so ffmpeg stderr never
 * embeds the title-slug PII) land in Sprint 6.0–6.3. Storage auth via Managed
 * Identity per D25; codec choices per D9 + D27 (libopus / built-in aac;
 * libfdk_aac forbidden).
 *
 * This file exists to prove the `@slaylist/shared` workspace import resolves
 * and type-checks (Sprint 0.2 acceptance).
 */

import { type Song, type SongState } from '@slaylist/shared';

// Compile-time check that the shared types are reachable from /transcoder.
const _typeCheck: { song: Pick<Song, 'id' | 'state' | 'libraryId'>; nextState: SongState } = {
  song: { id: 'placeholder', state: 'processing', libraryId: 'slaylist-home' },
  nextState: 'ready',
};

void _typeCheck;
