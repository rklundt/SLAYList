// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

/**
 * Shared types for SLAYList — the single source of truth for `Song`, roles,
 * and states across frontend, api, and transcoder.
 *
 * Anchored in:
 *   - D19: `libraryId` everywhere (renamed from `tenantId`).
 *   - D20: library-scoped authorization; the three roles are library-scoped.
 *   - D21: owner identity split — `ownerOid` is the authz key, `ownerDisplayName`
 *          is display-only PII, `createdByKid` is application metadata.
 *   - D29: this module is type-checked under `strict: true` +
 *          `noUncheckedIndexedAccess: true`.
 *   - D32: `ownerDisplayName` and `title` are PII / kid-name surfaces — never
 *          put them in logs; use `ownerOid` / `id` instead.
 */

/**
 * The four allowed lifecycle states a song record can be in.
 * `processing` — upload landed, transcode not yet complete.
 * `ready` — finished transcode written; playable.
 * `failed` — transcode failed after retries; surfaced for owner action.
 * `deactivated` — soft-deleted; hidden by default, recoverable until hard-delete.
 */
export const SONG_STATES = ['processing', 'ready', 'failed', 'deactivated'] as const;
export type SongState = (typeof SONG_STATES)[number];

/**
 * The three application roles (D20). Spelling/casing is locked — do not rename.
 * The two-tier admin model (library admin vs. platform admin) is a deferred
 * future addition; the current `admin` is implicitly admin of the sole library.
 */
export const ROLES = ['listener', 'uploader', 'admin'] as const;
export type Role = (typeof ROLES)[number];

/**
 * The default `libraryId` value for the single-family case (D19).
 * Not PII; safe to commit. If a multi-library future ever introduces real
 * per-family identifiers, those go in config — not in this constant.
 */
export const DEFAULT_LIBRARY_ID = 'slaylist-home';

/**
 * The canonical song record. Lives in Table Storage (D3); never in a JSON file.
 *
 * Field discipline:
 *   - `libraryId` is required on every record. Never assume one library (D19).
 *   - `ownerOid` is the ONLY field used for authz checks (D21). The Entra `oid`
 *     claim — stable, opaque.
 *   - `ownerDisplayName` is PII; for display only. Never log it (D32).
 *   - `createdByKid` is application metadata, distinct from `ownerDisplayName`
 *     (a parent may upload on behalf of a kid).
 *   - `title` is PII-adjacent (kids name songs with real first names); never log
 *     it — log `id` instead (D32).
 *   - `blobPath` is plumbing; the filename convention is in D8.
 */
export interface Song {
  /** Unique record id; also drives the blob shortid. Safe to log. */
  id: string;
  /** Application-level library label (D19). One value today: 'slaylist-home'. */
  libraryId: string;
  /** Display name. Contains PII (kids' names). Never log — log `id` instead (D32). */
  title: string;
  /** Entra `oid` claim. The only field used for authorization (D21). */
  ownerOid: string;
  /** Entra `preferred_username`. PII — display only, never log (D32). */
  ownerDisplayName: string;
  /** Optional: which kid made the song (distinct from `ownerDisplayName`). */
  createdByKid?: string;
  /** Optional: for later search. */
  genre?: string;
  /** Lifecycle state — one of `SONG_STATES`. */
  state: SongState;
  /** ISO timestamp when the record was created. */
  createdAt: string;
  /** ISO timestamp when the record was deactivated (soft-deleted). */
  deactivatedAt?: string;
  /** Pointer to the finished file in the `finished` blob container. */
  blobPath?: string;
  // TODO(Epic 6): narrow to a union (e.g., 'opus' | 'm4a') once the single
  // output format is decided in Sprint 6.1 per D9.
  /** Output format (e.g., 'opus', 'm4a'). String for now; narrowed in Epic 6. */
  format?: string;
  /** Size of the finished blob in bytes. Filled by transcoder. */
  sizeBytes?: number;
  /** Duration of the finished audio in seconds. Filled by transcoder. */
  durationSec?: number;
}
