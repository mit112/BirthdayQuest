# Multi-Tenant Occasions — Design

**Date:** 2026-08-20
**Status:** Approved design, pending implementation plan
**Scope:** Subsystem #1 of 4 — event scoping and identity

## Problem

BirthdayQuest is a single-occasion app. It cannot be shipped to the App Store as-is,
because it has no concept of an occasion at all.

Evidence from a five-part codebase audit:

- **No tenancy.** Five root collections at fixed paths. `game_state/main` is a singleton
  enforced by the security rules themselves (`firestore.rules:55`). Five user documents
  seeded at literal IDs `alex`/`sam`/`jordan`/`riley`/`morgan` (`DataSeeder.swift:84`).
  Not one of the five models carries an event, party, or tenant field.
- **No authoring surface.** 13 things a user can change in-app; 39 require code edits,
  the Firebase console, or re-seeding. The only content-creation screen is the secret
  dare, exposing three fields.
- **No authentication.** FirebaseAuth is linked but never called. Rules are
  `allow update: if true` on four collections. Firebase iOS config ships extractable in
  every App Store binary, so possession of the binary is full database write access.
- **No reward content.** All 8 seeded rewards ship `contentUrl: ""`
  (`DataSeeder.swift:182-212`), and `storage.rules:19` sets `allow write: if false` on
  `rewards/**`, so the app cannot fill them. Unlocking renders "Content loading soon".
- **No dates.** No date comparison logic exists anywhere. `currentDay` is an `Int` an
  admin increments by hand.

Consequence if shipped: 100 installs would not produce 100 occasions. They would produce
one occasion with 100 people contending for five character slots, sharing one point
balance and one timeline, with PIN `1234` granting anyone the admin panel.

## Product decisions

1. **Host + invited friends.** An event is the tenant. Concurrent occasions are isolated.
2. **Anonymous auth by default**, prompting Sign in with Apple on create-or-second-join.
   Firebase `linkWithCredential` upgrades the anonymous user in place, preserving uid and
   all existing data.
3. **Friends self-register** on join: name plus a bundled avatar. No host pre-authoring,
   no claim-stealing.
4. **Users participate in many occasions.** Flat list grouped by status in the UI. No
   persistent "circle" layer.
5. **All roles authenticated, celebrant on their own device.** No handover mode.
   Accepted cost: an occasion whose celebrant will not install the app cannot be rescued
   by the host. The invite flow must make that failure loud and early.
6. **Multi-occasion at launch:** birthday, anniversary, graduation, farewell, bachelor.
   Requires a rename, new icon, and new store listing (subsystem #4).
7. **Server as courier, device as archive.** Media transits Storage, the celebrant's
   device persists it, the server copy is deleted once fetched.
8. **No lifecycle state machine.** Host toggles `isOpen`. `occasionDate` is stored for
   sorting, reminders, and purge anchoring only — it gates nothing.

Accepted consequence of (8): nothing structurally prevents a celebrant from seeing their
reward list early. The points economy remains the gate, as today.

## Scope

**In:** event scoping, authentication, join and invite, self-registration, the occasion
list, per-event session lifecycle, media transit and local persistence, security rules,
and the five audit bugs listed below.

**Out (deliberately, so they are not quietly absorbed):**
- Host authoring surfaces — the 39-item gap list. Subsystem #2.
- Media upload UI and the reward content pipeline. Subsystem #3.
- Occasion-type template libraries, moderation, report/block, `PrivacyInfo.xcprivacy`,
  bundle ID, rename. Subsystem #4.

Subsystem #1 is a hard prerequisite for the rest; getting its schema wrong means
rewriting #2 through #4.

## Data model

```
events/{eventId}
  name, occasionType, celebrantName, celebrantUid?, hostUid,
  occasionDate, isOpen, createdAt

  participants/{uid}   name, avatarId, mode: contributor|celebrant, isHost: Bool
  challenges/{id}      as today, minus hardcoded IDs
  rewards/{id}         + fetchedBy: [uid]
  timeline/{id}
  state/main           GameState, shape unchanged

memberships/{uid}/events/{eventId}   mode, isHost, joinedAt

inviteCodes/{CODE}   -> { eventId, kind: contributor|celebrant }
```

Subcollections rather than flat collections with an `eventId` field. The deciding
argument is failure mode: with flat collections, isolation depends on every future query
remembering `.whereField("eventId", ...)`, and one omission leaks a stranger's family
videos. With subcollections that query cannot be written, because the path does not exist.

Two consequences worth noting. `state/main` becomes a legitimate singleton, so
`unlockRewardAtomically` and `completeChallengeAtomically` port with a path change and no
logic change — valuable because that code is currently untested. And every `GameBackend`
method gains an `eventId` parameter, which is mechanical and compiler-enforced.

**`mode` and `isHost` are separate fields.** An earlier draft used a single
`role: host|contributor|celebrant`, which conflates a permission with a play mode and
makes "host who is also the celebrant" unrepresentable. Split, the tab tree reads off
`mode` and the admin section off `isHost`.

**The membership mirror stays thin** — `mode`, `isHost`, and `joinedAt` only, no denormalized event
name or date. The occasion list reads event documents directly: 20 occasions is 20 small
reads on list open. Preferred over a fan-out that goes stale whenever a host renames an
occasion or toggles `isOpen`. Denormalize if it ever measurably hurts.

**Two invite codes per occasion:** a reusable contributor code and a single-use celebrant
code consumed on claim. This is what lets the celebrant reach the right role without host
intervention, which matters because there is no handover path.

## Enforcement: rules, not Cloud Functions

No Cloud Functions. Rules carry the enforcement that a server would otherwise provide.

Note on cost, which changes nothing but corrects a common assumption: as of
2024-10-30, Cloud Storage for Firebase requires the Blaze plan for new projects, and
Spark projects receive 402/403 on all bucket calls. This app already uses Storage, so a
clone already requires a billing account. Functions were not the deciding factor.

The reason to omit them is engineering weight: a second language and runtime in a Swift
repo, a deploy pipeline, CI complexity, and a cold start on the join path — the exact
moment a new user is deciding whether the app works.

Mechanisms:

- **Create event** — client `WriteBatch`, atomic. Rules: `allow create: if isHost(eventId)`.
  A malicious host can only write malformed content into their own event, which they
  already control.
- **Invite code uniqueness** — Firestore `allow create` fires only when the document does
  not exist, so `inviteCodes/{CODE}` is collision-safe for free. A clash returns
  permission-denied and the client retries with a new code.
- **Join** — `inviteCodes` is `allow read: if false`, so it cannot be enumerated. The
  joiner asserts the code in their `participants/{uid}` create, and rules validate it via
  `get()`; rules-internal reads bypass rules, so the collection stays opaque. An 8-char
  code from an unambiguous 32-symbol alphabet is ~2^40 combinations and every guess costs
  a write.
- **Purge** — the celebrant's device deletes the Storage object after download. They are
  the last recipient by definition, so no scheduled job is needed. A GCS object lifecycle
  rule on the bucket is the backstop for the celebrant who never opens the app.
- **Expiry reminders** — local notifications scheduled on the celebrant's device, which
  already knows `occasionDate`. No FCM, therefore no server.

Revisit Functions if abuse appears or template velocity demands server-side updates.
That is a decision better made with data than in advance.

### Media gating

Storage paths carry `eventId` so rules can extract it:

```
events/{eventId}/rewards/{rewardId}/{fileName}
events/{eventId}/proofs/{challengeId}/{fileName}
```

Storage rules gate on Firestore membership via
`firestore.exists(/databases/(default)/documents/events/$(eventId)/participants/$(request.auth.uid))`.
Cross-service rules permit **two unique Firestore document lookups per evaluation**;
repeat calls on the same document are cached and free. One membership check per request
fits comfortably. These reads bill against the Firestore quota.

This replaces today's world-readable permanent download URLs, under which any uploaded
family video is effectively a public link forever.

## Client architecture

Session splits in two:

- **`AppSession`** — auth, uid, Apple-link state, memberships. Knows nothing about any
  occasion.
- **`EventSession`** — created on opening an occasion; holds `eventId`, the current
  participant, and the `GameState` listener. Destroyed on leave.

This also retires a workaround. CLAUDE.md notes that named listener keys prevent
collisions; with listeners owned by an `EventSession` whose lifetime is the occasion's,
they are scoped by construction and torn down together.

```
RootView
 ├ .launching     splash
 ├ .empty         [Create occasion] [Join with code]
 └ .occasions     My Occasions  →  EventContainerView(eventId)
                                     mode == .celebrant → CelebrantTabView
                                     else               → ContributorTabView
                                     isHost → admin section in Profile
```

`AppState`'s four cases and the single `bq_selected_character_id` string are replaced.
`SessionManager` is a rewrite, not an edit.

**`CharacterSelectView` is relocated, not deleted.** Self-registration removes
swipe-to-find-yourself, but its 583 lines of carousel and card art are the best-looking
surface in the app. The carousel becomes the in-occasion roster; `CharacterCardView`
styling becomes the join-time avatar picker.

**`AvatarView` requires real work, as a privacy fix.** It switches on five hardcoded
names then falls through to a live `api.dicebear.com` request. With arbitrary user names,
every avatar render becomes an undisclosed third-party call leaking a display name. Fix:
bundle an avatar set, pick at join, drop DiceBear. `avatarId` — currently seeded,
documented, and unread — becomes the field that drives it.

**New component: `MediaStore`, an actor.** Resolves a reward to a local file URL,
downloading and persisting on first unlock, then recording `fetchedBy`. Files are written
to **Documents, not Caches**: Caches is purged by iOS under pressure, and these files must
ride the user's iCloud backup. `isExcludedFromBackup` must not be set. The four content
renderers switch from remote URL to local file URL, which removes buffering and network
failure paths from playback entirely.

**Unchanged:** `DesignSystem`, all four content renderers, `SkeletonView`,
`TimelineBackgroundView`, `FloatingParticlesView`, the transaction bodies,
`RewardsCarouselView`, `TimelineView`, most of `ChallengeDetailView`. `MockGameBackend`
and `ViewModelTests` need an `eventId` sweep and continue to work.

## Error handling

The new failure mode is **media expiry**: the celebrant never opens the app, the backstop
passes, the object is purged. This must not present as "Content loading soon". Required:
local-notification reminders before the backstop, an explicit "this gift expired" state,
and a recovery path — the contributor still holds the original locally, so "ask Sam to
re-send" is real rather than aspirational.

Distinct cases replacing today's generic "Oops": invalid or exhausted invite code,
membership revoked mid-session, upload failed, media expired, offline.

Permission-denied becomes an *expected* event once membership can be revoked, not a bug.

Offline mostly works already — Firestore persistent cache is enabled at
`BirthdayQuestApp.swift:15-17` and writes queue. Create and join are the exceptions:
both hard-require network and need explicit offline copy rather than a spinner, which is
precisely the trap `bootstrap()` falls into today.

## Testing

Two tiers.

- **`MockGameBackend`** continues to cover ViewModels quickly, after an `eventId` sweep.
- **Firebase emulator integration tests** cover what a mock structurally cannot.

The emulator is now justified rather than gold-plating, for two reasons. The transaction
logic CLAUDE.md lists as untested is being moved to a new path, and untested code plus a
migration is the worst combination to leave alone. More importantly, the entire argument
for subcollections is that cross-event access is impossible — that is a claim, and with
Functions omitted, rules carry the whole enforcement burden. Untested rules are all that
stand between strangers and each other's family videos.

Required rules cases: non-member denied, member allowed, cross-event read denied, client
create denied outside host scope, `inviteCodes` unreadable, Storage membership gate,
celebrant-only delete.

Honest cost: `@firebase/rules-unit-testing` is JavaScript, so this adds a JS test suite
to a Swift repo plus an emulator job in `ci.yml`. There is no Swift path to testing rules.

## Migration

Do not migrate. The existing occasion has happened; lifting one historical event into a
still-settling schema produces data nobody will open again.

Instead: export the media, which is the only irreplaceable content in that project, and
leave the old Firebase project untouched as a read-only archive. The new schema starts
clean, without legacy-shaped compromises baked into a design that must serve strangers
for years.

## Audit bugs fixed within this scope

These sit inside the blast radius, so they are fixed here rather than filed.

1. **Rules make the seeder impossible.** `firestore.rules:26` denies `create` on `users`,
   but `DataSeeder.seedUsers()` creates those documents. It throws PERMISSION_DENIED,
   exiting the outer `do` block, so `seedGameState()` and both subsequent checks never
   run. `game_state/main` is never created, `gsDoc.exists` stays false, and the failure
   repeats every launch — visible only as a swallowed `logger.error`. Anyone following
   `README.md:151-186` gets a permanently empty character-select screen. Resolved
   structurally: seeding becomes host-scoped event creation under rules that permit it.
2. **Listener errors never clear `isLoading`.** `FirestoreService.swift:42-45` and three
   siblings return early on error without calling the completion handler, producing an
   infinite shimmer with no error and no retry. Critical now that permission-denied is
   expected. Completion handlers must carry a `Result`.
3. **`putDataAsync` sends no `StorageMetadata`.** `FirestoreService.swift:414` omits
   `contentType`, which defaults to `application/octet-stream`, while `storage.rules:24`
   requires `image/*`. If confirmed against a live bucket, every proof photo upload
   returns 403 — and `ChallengeSubmissionViewModel.swift:127-131` swallows it into
   "Submission failed. Try again!" with no logging. **Verify before implementation**; it
   may mean photo proof has never worked outside the original developer's project.
4. **Timeline titles parsed from literal prefixes.** Written as `"Completed: …"` in four
   places and parsed back at `TimelineNodeView.swift:254`. Use the `type` field already on
   the model. Mandatory regardless, since multi-occasion copy cannot live in English-only
   string prefixes.
5. **`bootstrap()` blocks on `batch.commit()`.** `SessionManager.swift:88` awaits seeding,
   and `WriteBatch.commit()` resolves only on server acknowledgement, so an offline cold
   launch hangs on the splash screen indefinitely. Disappears once seeding is host-scoped
   event creation.

Also delete `Reward.defaultPointCost` (`Models/Reward.swift:22-29`) — dead code that
contradicts the seed, claiming audio costs 75 where the seeder charges 50.

## Risks

- **Celebrant will not install.** No handover path by decision (5). Mitigate by
  surfacing celebrant-not-joined prominently to the host from the moment the occasion is
  created, not on the day.
- **Rules become load-bearing.** With no Functions, a rules mistake is a data breach
  rather than a bug. Mitigated only by the emulator test suite; that suite is not
  optional.
- **Media expiry is permanent loss.** Mitigated by reminders, an honest expired state,
  and contributor re-send. Residual risk remains and is accepted as the cost of bounded
  storage.
- **Client-side purge depends on client cooperation.** GCS lifecycle is the backstop, so
  worst case is delayed deletion rather than unbounded retention.
- **`putDataAsync` finding is unverified.** Requires a live bucket to confirm. Verify
  first; it may change the size of the upload work.
