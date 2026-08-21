# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a SwiftUI iOS app using Xcode with Swift Package Manager dependencies.

```bash
# Build for simulator
cd BirthdayQuest
xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# Run tests
xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Or use Cmd+R / Cmd+U in Xcode. The XcodeBuildMCP tools are also available.

## Architecture

**MVVM + Services** — Models → Services → ViewModels → Views

### Dependency Injection
Every ViewModel takes `service: GameBackend = FirestoreService.shared`, and anything touching auth
takes `auth: AuthProviding = AuthService.shared`. Never reference `FirestoreService.shared`
anywhere else — inject the protocol instead, so tests can pass `MockGameBackend` /
`MockAuthProviding` (in `BirthdayQuestTests/`). Views must not touch the backend or auth at all.

### Services
- **AppSession** — auth state, uid, Apple-link state, and the user's occasion list. Knows nothing
  about any single occasion. Drives root routing (`.launching` / `.empty` / `.occasions`).
- **EventSession** — one occasion's scope: `eventId`, the current `Participant`, the `GameState`
  listener. Created on opening an occasion, destroyed on leaving. Owns and tears down **only its
  own** listener keys.
- **AuthService** — anonymous sign-in, Apple linking via `linkWithCredential` (preserves the uid,
  which matters because participants and memberships are keyed by it). Behind `AuthProviding`;
  `FirebaseAuthProvider` is the only type touching `Auth.auth()`.
- **FirestoreService** — All Firestore CRUD, behind the `GameBackend` protocol. Every method takes
  an `eventId`. Uses **transactions** for reward unlocks (server-side balance re-check) and
  challenge completions (idempotency guard). Occasion creation is **two-phase** — see below.

### Key Firestore Patterns
- **Timestamps:** Always use `Timestamp(date: Date())`, never `FieldValue.serverTimestamp()` (breaks Codable)
- **GameState parsing:** Manual dictionary parsing with `NSNumber?.intValue`, NOT Codable (Int64/NSNumber mismatch)
- **Listener keys are event-scoped:** `ListenerKey.scoped(_:eventId:)`. Two view models sharing one
  key silently kill each other's listener — `AdminViewModel` uses `admin_rewards@<eventId>` for
  exactly this reason. Never call a global `removeAllListeners()` from a per-event object.
- **Occasion creation is two-phase, and must stay that way.** Firestore evaluates batched writes
  against *committed* state. Phase 1 writes the event document alone; phase 2 batches the host
  participant, `state/main`, and the membership mirror. The rules gate the latter two on
  `events/{id}.hostUid` — **not** on participant membership — precisely so that batch can commit.
  Gating them on membership makes every occasion creation fail. There is a rules test pinning this.
- **Event documents are updated, never full-replaced.** `hostUid` is immutable in the rules, so a
  `setData` that omits it is denied. Use `updateData` for any edit of an existing event.
- **`@DocumentID` only decodes through Firestore's decoder.** A plain `JSONDecoder` throws
  `keyNotFound` on `"id"` regardless. Never hand-write `init(from:)` on a model carrying
  `@DocumentID` — it suppresses the memberwise init *and* silently nulls every loaded id.
- **Uploads must send `StorageMetadata` with an explicit `contentType`.** `putData` does not infer
  one from the path; without it the object uploads as `application/octet-stream` and the Storage
  rules reject it.

### Design System
All UI tokens live in `DesignSystem.swift` under the `BQDesign` namespace (colors, typography, spacing, radius, shadows, animations). Use these instead of hardcoded values.

### Collections
All event content lives under `events/{eventId}` subcollections. Isolation is by **path**, not by
query discipline — a client cannot express a query reaching another occasion, because the path does
not exist for them. Never reintroduce a root-level content collection.

| Path | Notes |
|---|---|
| `events/{eventId}` | `name`, `occasionType`, `celebrantName`, `hostUid`, `occasionDate`, `isOpen`, `createdAt`, `contributorCode`, `celebrantCode`. Invite codes live **here**, not in a client-readable collection. |
| `events/{id}/participants/{uid}` | `name`, `avatarId`, `mode` (`contributor`\|`celebrant`), `isHost`, `usedCode`. `mode` and `isHost` are separate — "host who is also the celebrant" is representable. |
| `events/{id}/challenges/{id}` | Includes secret challenges (`isSecret: true`) |
| `events/{id}/rewards/{id}` | Plus `fetchedBy: [String]?` for media purge tracking |
| `events/{id}/timeline/{id}` | Append-only by rule (`allow update, delete: if false`) |
| `events/{id}/state/main` | GameState. A legitimate singleton now that it is event-scoped. |
| `memberships/{uid}/events/{id}` | Thin mirror: `mode`, `isHost`, `joinedAt`. No denormalized event name/date. |
| `inviteCodes/{CODE}` | Uniqueness reservation + code→event resolution only. `allow get` / **deny `list`** so a known code resolves but the collection cannot be enumerated. **Authorization does not flow through here** — joins are authorized against the event document's own code fields. |

**Wire field names are load-bearing.** The rules compare against them literally, and no Swift test
catches a rename — it fails at runtime with permission-denied.

## Important Conventions

- ViewModels are `@MainActor final class`. Views read `GameState` and the current participant from
  the `EventSession` `@EnvironmentObject`.
- Challenge submission uses a universal 3-option picker (Photo / Text / Done) — no per-challenge submission types.
- 2-in-1 challenges have `optionBTitle` / `optionBDescription` optional fields.
- Reward content types: video, audio, text, image. Image rewards use `contentUrls: [String]` array; others use `contentUrl: String`.
- Identity is a Firebase **anonymous uid**, upgradeable to Sign in with Apple in place. There is no
  device-locked character claim and no PIN.
- Avatars are bundled (`AvatarCatalog`); `AvatarView` has both `init(avatarId:)` and `init(name:)`,
  the latter mapping via a **stable FNV-1a hash** — never `hashValue`, which is per-process seeded
  and would reshuffle every launch. DiceBear and its network call are gone.

## Testing

Two tiers, and both must stay green:
- `xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BirthdayQuestTests test`
  — **always scope to `BirthdayQuestTests`.** A bare `test` also runs `BirthdayQuestUITests`, which
  boots a simulator and launches the app; it is slow, thrashes memory, and hangs in teardown. CI
  already passes `-skip-testing:BirthdayQuestUITests`.
- `cd firebase-tests && npm test` — the emulator rules suite. With no Cloud Functions, rules carry
  the entire enforcement burden, so this suite is not optional. Run it after any rules change.
- Run `swiftlint` from the **repo root**; from the nested source dir it misses `.swiftlint.yml` and
  reports hundreds of phantom violations.

## Dependencies (SPM)
- **Firebase SDK** — FirebaseCore, FirebaseFirestore, FirebaseStorage. FirebaseAuth is linked but **never imported or called** — the app does no authentication.
- **ConfettiSwiftUI** — Celebration animations
- Built-in: AVFoundation, AVKit, Combine

## Project Details
- Bundle ID: `com.example.birthdayquest`, `DEVELOPMENT_TEAM` is empty. Set signing in Xcode and keep that change out of commits (`skip-worktree` is no longer used).
- Deployment Target: iOS 26.0
- Source root: `BirthdayQuest/BirthdayQuest/` (nested due to Xcode project structure)
- GoogleService-Info.plist is gitignored — each developer needs their own Firebase project. It is NOT a build input (folder-synced groups), so the app builds without it and crashes at launch.
- Security rules live in `firestore.rules` / `storage.rules`, deployed via `firebase deploy --only firestore:rules,storage`.

## Known Gaps (do not "discover" these as new)
- The atomic transaction logic (`unlockRewardAtomically`, `completeChallengeAtomically`,
  `adminForceUnlockReward`) is still NOT covered by tests. It was ported to the event-scoped paths
  with no logic change. Proving the balance re-check and idempotency guards needs a Swift↔emulator
  integration harness that does not exist.
- **Any member can rewrite `state/main` (point balances) and flip `rewards.isUnlocked`.** The rules
  gate those on membership only. This is the pre-existing no-Functions trust model, not a
  regression — but it is now a stranger-facing assumption rather than a family one.
- Near-zero accessibility: a few `accessibilityLabel`s were added on the new occasion surfaces, but
  there is no Dynamic Type or reduce-motion handling against ~10 `repeatForever` animations.
- `fetchMyOccasions` fans out **serially** — N sequential round trips on the occasion-list cold
  path. A `withThrowingTaskGroup` would fix it.
- The 3 `BirthdayQuestUITests` were written against the deleted character-select flow. They compile
  but are not run and will need rewriting.
- Points economy: 13 challenges award 715 pts, 8 rewards cost 750. The gap is intentional — secret challenges (50 pts each) close it.

### Audit bugs — status after the event-scoping migration

All eight were confirmed by reading the code on 2026-08-20. Do not re-discover them as new.

**Fixed on `feat/event-scoping-and-identity`:**
- **Rules made the seeder impossible.** `firestore.rules` denied `create` on `users` while
  `DataSeeder.seedUsers()` created those docs, throwing PERMISSION_DENIED, exiting the outer `do`
  block so `game_state/main` was never created — a permanently empty character-select screen for
  anyone who cloned the repo. **Resolved structurally: `DataSeeder` is deleted**; seeding is now
  host-scoped occasion creation.
- **Listener errors never cleared `isLoading`.** Completions now carry `Result` and every error
  path calls back. Critical now that permission-denied is an *expected* event.
- **`putDataAsync` sent no `StorageMetadata`.** VERIFIED TRUE from firebase-ios-sdk source
  (`putData` never sets a contentType; `MIMETypeForExtension(nil)` returns the literal
  `application/octet-stream`), so every proof photo upload 403'd, swallowed with no logging. Now
  sends `image/jpeg`, pinned by a rules test *and* a Swift assertion.
- **`bootstrap()` blocked on a server ack.** Gone with `DataSeeder`.
- **Timeline titles parsed off literal prefixes.** Now derived from `TimelineEvent.type`.
- **`RewardContentType.defaultPointCost`** (misnamed `Reward.defaultPointCost` in the old docs)
  deleted — dead code contradicting the seed.

**Still open — deferred to Plan 2:**
- Two silent `RewardContentSheet` defects: a text reward with no content renders the placeholder as
  if it were the real gift; a `contentUrls` array with exactly one element falls through to the
  different `contentUrl` field and shows "Content loading soon".
- `README.md` still needs correcting (Task 16): it describes `DataSeeder` populating Firestore on
  first launch, and claims a missing `GoogleService-Info.plist` "crashes at launch with a message
  pointing you here" — `FirebaseApp.configure()` is called bare, so it dies on a raw assertion.

## Direction (as of 2026-08-20)

The app is multi-tenant. Subsystem #1 (event scoping + identity) is **15 of 16 tasks implemented**
on `feat/event-scoping-and-identity` — 20 commits, build green, 96 Swift tests + 66 emulator rules
tests passing.

- Design: `docs/superpowers/specs/2026-08-20-multi-tenant-occasions-design.md`
- Plan: `docs/superpowers/plans/2026-08-20-event-scoping-and-identity.md`
- **Execution record: `.superpowers/sdd/2026-08-20-event-scoping-and-identity/`** (git-ignored)
  holds `rulings.md` — 61 decisions taken against the plan, each with what it costs if wrong — and
  `progress.md`. **Read `rulings.md` before touching this subsystem**; the plan alone is misleading
  in ~15 places where a ruling overrode it.

**Not done:** Task 16 (media archive script + README corrections) and the final whole-branch review.

**Manual steps required before any of this works against a live project** — none are detectable by
any test:
1. Xcode: add the **Sign in with Apple** capability.
2. Firebase console: enable the **Anonymous** and **Apple** providers.
3. Run Task 16's archive script **before** `firebase deploy` — the new rules deny all access to the
   old `rewards/**` and `proofs/**` prefixes.

Remaining subsystems, unchanged: #2 host authoring (the 39-item gap list), #3 media pipeline
(`MediaStore`, server-as-courier), #4 compliance (moderation, `PrivacyInfo.xcprivacy`, real bundle
ID, rename away from "BirthdayQuest", store listing).

Decisions already made and still binding: no Cloud Functions (rules carry all enforcement); no
lifecycle state machine (`isOpen` is a host toggle, `occasionDate` is for sorting and purge
anchoring only); five occasion types at launch; celebrant must install the app, with **no handover
mode** — which is why the host panel surfaces celebrant-not-joined prominently.
