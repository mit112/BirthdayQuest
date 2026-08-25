# Media Lifecycle — Design (Subsystem #3, final slice)

**Date:** 2026-08-24
**Status:** Approved for implementation (autonomous session)
**Scope owner:** closes the last open piece of the media pipeline (subsystem #3).

## Problem

Reward media (photo/video/audio gifts) is uploaded to Storage as object *paths*, downloaded by the
celebrant's device through an authenticated reference, and persisted to Documents as a local archive
("server as courier, device as archive"). Three gaps remain from slices 1–3:

1. **Server objects live forever.** `MediaStore.purge` exists but has no production caller. Every
   gift's Storage object persists until an out-of-band GCS lifecycle backstop, unbounded in cost.
2. **No honest "expired" state.** `RewardContentPresentation.resolve` collapses *every* media-fetch
   failure into `.unavailable` — whose copy says "Nothing was added to this gift." When media *was*
   authored but the server object is gone, that is a lie attributed to a real friend.
3. **No warning before loss.** An unopened media gift is never downloaded, so it is the thing that
   disappears at cleanup — and the celebrant is never told to open it in time.

## Non-goals (deferred to their own slices — explicitly out of scope here)

- **Full re-send round-trip.** A contributor re-uploading an expired gift needs a new reward field
  (a "re-send requested" signal in the gameplay rules tier), a `firestore.rules` allow-list change,
  contributor-side UI to re-enable authoring after unlock, and a reckoning with the
  content-immutable-after-open invariant. That is a subsystem, not this slice. The `.expired` state
  here points the celebrant to reach out to the contributor; it does not wire the round-trip.
- **Streaming / file-URL upload.** `uploadRewardMedia` loads the whole (≤200 MB) clip into memory
  via `Data(contentsOf:)`. Replacing that with a streaming upload is an upload-API change unrelated
  to lifecycle; the 200 MB cap already bounds it. Deferred.
- **Push / local notifications** for expiry reminders. No notification infrastructure exists. The
  reminder is an in-app banner only.

## Design

### Data flow (unchanged spine)

Contributor uploads media → Storage object at a path → path stored in `reward.contentUrl` /
`contentUrls` → celebrant unlocks → `MediaStore.localURLs` downloads+persists to
`Documents/RewardMedia/<eventId>/<rewardId>/<file>` and records `fetchedBy += celebrantUid` → the
sheet renders the local `file://` URL. **The celebrant is the sole recipient of every gift**, so a
reward whose local archive exists on the celebrant's device is safe to remove from the server.

### Component 1 — `MediaLifecycle` (pure policy, new)

A namespace of pure, side-effect-free date math and predicates — the single source of truth for
"when." Mirrors the `WireKey` / `GameState.init(wire:)` pattern of keeping load-bearing logic out
of the I/O types so it is directly unit-testable.

```
enum MediaLifecycle {
    static let gracePeriod: TimeInterval   // = 30 days
    static let reminderWindow: TimeInterval // = 7 days

    /// The instant a reward's server media becomes eligible for cleanup.
    static func expiry(occasionDate: Date) -> Date            // occasionDate + gracePeriod
    /// Past expiry as of `now`.
    static func isExpired(occasionDate: Date, now: Date) -> Bool
    /// Within the reminder window before (or past) expiry as of `now`.
    static func isWithinReminderWindow(occasionDate: Date, now: Date) -> Bool
}
```

`occasionDate` is the anchor (as documented). Expiry is a property of the *occasion*, applied to all
its media rewards uniformly — not a per-reward field, so no schema/rules change.

### Component 2 — `MediaStore` purge sweep (extends existing actor)

Add one method; keep the disk/network knowledge inside the actor that already owns it:

```
/// Celebrant-only. For each reward whose media this device already holds locally AND whose occasion
/// is past media expiry, delete the remote Storage objects (idempotent, best-effort). Bounds
/// storage cost without ever deleting an object the device has not archived. Returns the count
/// purged (for logging/tests).
func purgeExpiredArchived(rewards: [Reward], eventId: String, occasionDate: Date, now: Date) async -> Int
```

Eligibility per reward, checked in order (all must hold):
1. The reward has media paths (`storagePaths` non-empty).
2. `MediaLifecycle.isExpired(occasionDate:, now:)`.
3. **Every** local file for the reward exists on disk *right now* (not merely `fetchedBy`-recorded —
   the archive could have been cleared; trusting the flag alone could delete the last copy).

Only then `transfer.delete(path:)` each path. `delete` is already idempotent (objectNotFound = ok).

The existing single-reward `purge(reward:eventId:)` stays (it is the primitive the sweep and the
Storage rules doc-comment describe).

### Component 3 — `.expired` presentation state

Add a case and classify the download failure so the copy can be honest:

- `MediaStore.localURLs` translates a Storage **objectNotFound** into a typed
  `MediaStoreError.objectMissing`; all other errors (network, auth) pass through unchanged.
- `RewardContentPresentation`: new `case expired`. `resolve` maps a thrown `objectMissing` →
  `.expired`; any other throw stays `.unavailable` (today's behavior). A reward whose files are
  **already on disk** never downloads, so it renders normally even after the server object is purged
  — `.expired` is reachable only when the object is gone *and* there is no local archive.
- `RewardContentSheet` renders `.expired` with distinct, honest copy: e.g. *"This gift from
  {fromName} isn't available anymore. Ask them to send it again."* — no confetti, no success haptic
  (same suppression `.unavailable` already gets), and a warning-level log line. Text rewards never
  reach `.expired` (they have no Storage object).

### Component 4 — Expiry reminder banner (celebrant, rewards view)

In `RewardsCarouselView` / `RewardsViewModel`, show a dismissible banner when **all** hold:
- `event.isCelebrant`
- `MediaLifecycle.isWithinReminderWindow(occasionDate:, now:)`
- there exists a media reward with `!isUnlocked` (an unopened media gift = the thing that will be
  lost; a text gift or an already-unlocked/archived gift is not at risk).

Copy names the date and the action: *"Your gifts get tidied up after {date}. Open them to keep them
on this device forever."* Tapping does nothing destructive; it is informational. Purely derived from
the already-loaded reward list + occasion date — no disk or network read on the main actor.

### Purge trigger point

`RewardsViewModel`, celebrant-only, once per appearance after the first rewards snapshot: fire the
`MediaStore.purgeExpiredArchived` sweep in a detached best-effort `Task`. Never blocks UI; failures
are logged, not surfaced. Host devices never purge (they are not recipients and the Storage rules
would deny a host deleting media it never archived anyway — but we gate on `isCelebrant` regardless).

## Error handling

- Purge is best-effort and idempotent; a failure logs and is dropped (media is already local, or
  will fall to the GCS backstop).
- `objectMissing` is the *only* failure promoted to a user-visible state (`.expired`); everything
  else keeps the existing behavior so a transient network blip is not mislabeled "expired."
- No new failure can fail an unlock or a resolve harder than today.

## Rules impact

**None.** Purge uses the celebrant-or-host Storage delete permission that slice 1 already granted;
`markRewardFetched` is already in the gameplay tier. No `firestore.rules` / `storage.rules` change →
the emulator rules suite is intentionally not re-run for this slice.

## Testing

- `MediaLifecycle`: expiry/reminder math at boundaries (exactly at expiry, one second before/after,
  reminder window edges). Pure, deterministic (`now` injected).
- `MediaStore.purgeExpiredArchived`: via the existing `MediaTransferring` fake + a real temp
  `baseDirectory`. Cases: not-expired → 0 purges; expired but files absent on disk → 0 purges (the
  archive-before-purge invariant); expired and files present → deletes exactly those paths; text
  reward → skipped; idempotent re-run.
- `RewardContentPresentation.resolve`: `objectMissing` → `.expired`; other throw → `.unavailable`;
  files-on-disk (fake returns URLs) → renders; each assertion also verified to *change* when the
  mapping is removed (no vacuous green).
- Reminder condition: pure predicate tested directly across the isCelebrant / window / unopened-media
  matrix.

## Rulings

- **ML1 — Purge only at/after expiry, never immediately on fetch.** Preserves redownload during the
  grace window (a celebrant reinstall inside grace is recoverable) and gives the reminder a true
  story. Cost of wrong: aggressive purge would lose media on any device-loss before a backup exists.
- **ML2 — Purge verifies files on disk now, not `fetchedBy`.** `fetchedBy` is a historical flag; the
  archive can be cleared. Cost of wrong: deleting the last copy.
- **ML3 — Expiry is occasion-level (`occasionDate + grace`), not a per-reward field.** Avoids a
  schema + rules change and matches the documented purge anchor. Cost of wrong: cannot express
  per-gift lifetimes (not a requirement).
- **ML4 — `.expired` is derived from objectNotFound, not a persisted flag.** No doc write on purge →
  no rules change, and contributors' devices need not know. Cost of wrong: a transient objectNotFound
  (shouldn't occur pre-upload) could momentarily read as expired.
