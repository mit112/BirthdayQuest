# Proof-Photo Path Migration — Design

**Date:** 2026-08-25
**Scope:** Close the proof-photo download-URL leak (the reward-media half was closed in #3 slice 1).

## Problem
`FirestoreService.uploadProofData` returns `ref.downloadURL().absoluteString` — a long-lived tokened
URL (`?alt=media&token=…`) that is persisted in `challenge.proofUrl`, BYPASSES the Storage rules, and
outlives membership revocation. `ChallengeDetailView.photoProofView` renders it via `AsyncImage(url:)`.
A revoked member (or anyone who ever saw the URL) can still fetch the proof photo forever.

## Fix (mirror the reward-media pattern: store the object PATH, render via authenticated download)
1. `uploadProofData` returns the Storage object **path** (drop `downloadURL()`; `return path`). The
   `image/jpeg` `StorageMetadata` is UNCHANGED — do not touch it (a Storage rule + its emulator test
   pin `image/*`, and the SDK won't infer a content type).
2. `challenge.proofUrl` now holds a path, not a URL (same field, same gameplay rules tier — no rules
   change). No live data exists (app never shipped) ⇒ no migration.
3. New narrow protocol `ProofMediaLoading { func localURL(forPath:eventId:) async throws -> URL }`,
   conformed by `MediaStore` (interface segregation — the proof renderer must not depend on
   reward-purge methods, and the reward mocks stay untouched). It downloads+persists a single object
   through an authenticated `MediaTransferring` reference into a `SharedMedia/<eventId>/` cache dir;
   no `fetchedBy`, no purge. Translates Storage objectNotFound → `MediaStoreError.objectMissing`.
4. New `ProofImageView(path:eventId:loader:)` resolves the path to a local `file://` URL in a `.task`
   and renders the SAME success/failure/empty UI the existing `AsyncImage` branch used. Replaces the
   `URL(string: proofUrl)` branch in `ChallengeDetailView.photoProofView`; `eventId` comes from the
   `event` `@EnvironmentObject`.

## Security outcome
No tokened URL is ever persisted. Reads go through an authenticated reference honoring the existing
member-read Storage rule, so a revoked member is denied. **No `storage.rules`/`firestore.rules`
change** → the emulator rules suite is intentionally not re-run.

## Testing
- `MediaStore.localURL(forPath:eventId:)`: download-on-miss, cache-hit skips download, objectNotFound
  → `objectMissing` (reuse `FakeMediaTransfer` + temp `baseDirectory`).
- `MockGameBackend.uploadProofData` returns a deterministic path (mirror `uploadRewardMedia`'s stub);
  confirm no existing test asserted a URL shape (verified: none do).

## Deferred (unchanged): proof-media purge/expiry (the reward-media lifecycle exists now; proofs are a
later application of the same MediaStore spine, out of scope here).
