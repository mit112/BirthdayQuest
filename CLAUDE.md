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
Every ViewModel and `SessionManager` takes `service: GameBackend = FirestoreService.shared`.
Never reference `FirestoreService.shared` anywhere else — inject `GameBackend` instead, so tests
can pass `MockGameBackend` (in `BirthdayQuestTests/`). Views must not touch the backend at all.

### Services (singletons)
- **SessionManager** — App state hub (`@EnvironmentObject`), manages navigation, character selection, and real-time GameState sync
- **FirestoreService** — All Firestore CRUD, behind the `GameBackend` protocol. Uses **transactions** for both reward unlocks (server-side balance re-check) and challenge completions (idempotency guard: bails if already completed). Batches are used only for seeding. Named listener keys prevent collisions.
- **DataSeeder** — Seeds Firestore collections on first launch; skips if data exists

### Key Firestore Patterns
- **Timestamps:** Always use `Timestamp(date: Date())`, never `FieldValue.serverTimestamp()` (breaks Codable)
- **GameState parsing:** Manual dictionary parsing with `NSNumber?.intValue`, NOT Codable (Int64/NSNumber mismatch)
- **Listener naming:** Unique string keys per view to prevent listener collisions
- **Media URLs:** HTTPS download URLs stored directly in Firestore docs (no runtime URL resolution)

### Design System
All UI tokens live in `DesignSystem.swift` under the `BQDesign` namespace (colors, typography, spacing, radius, shadows, animations). Use these instead of hardcoded values.

### Collections
| Collection | Key doc(s) |
|---|---|
| `users` | 5 characters: alex, sam, jordan, riley, morgan |
| `challenges` | 13 seeded + secret (user-created, `isSecret: true`) |
| `rewards` | 8 seeded rewards: audio=50✦, video=100✦. No text/image rewards are seeded (the model supports them). All ship with an empty `contentUrl`. |
| `timeline_events` | Append-only, created atomically with challenge/reward operations |
| `game_state` | Single doc `main` — all progress tracking |

## Important Conventions

- ViewModels are `@MainActor final class` — do NOT read `SessionManager.shared.gameState` in computed properties (not observable). Views read it from `@EnvironmentObject`.
- Challenge submission uses a universal 3-option picker (Photo / Text / Done) — no per-challenge submission types.
- 2-in-1 challenges have `optionBTitle` / `optionBDescription` optional fields.
- Reward content types: video, audio, text, image. Image rewards use `contentUrls: [String]` array; others use `contentUrl: String`.
- Character claiming uses device-locked `deviceId` in UserDefaults (`bq_selected_character_id`).

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
  `adminForceUnlockReward`) is NOT covered by tests. `MockGameBackend` replaces that logic rather
  than verifying it — proving the balance re-check and idempotency guards needs the Firebase
  emulator suite, which is not wired up.
- Zero accessibility support: no `accessibilityLabel` anywhere, no Dynamic Type, no reduce-motion handling.
- Hardcoded `overridePin = "1234"` in `CharacterSelectViewModel` is the only access control.
- Points economy: 13 challenges award 715 pts, 8 rewards cost 750. The gap is intentional — secret challenges (50 pts each) close it.
- `AvatarView` falls back to the live `api.dicebear.com` HTTP API for any name outside the 5 known characters.
- `avatarId` is seeded and documented but unused; `AvatarView` switches on `name`.

### Verified bugs found in the 2026-08-20 audit (not yet fixed)

All confirmed by reading the code; do not re-discover them as new findings.

- **The shipped rules make the shipped seeder impossible.** `firestore.rules:26` denies
  `create` on `users`, but `DataSeeder.seedUsers()` creates those docs. It throws
  PERMISSION_DENIED, which exits the outer `do` block at `DataSeeder.swift:43-45`, so
  `seedGameState()` and both later checks never run. `game_state/main` is never created,
  `gsDoc.exists` stays false, and the failure repeats every launch — the only symptom is a
  swallowed `logger.error("Seed error:")` and a permanently empty character-select screen.
  Same story for `rewards` (`:41`) and non-secret `challenges` (`:33`). **Anyone cloning the
  repo and following `README.md:151-186` gets a broken app**; Firestore test mode is the only
  path that works.
- **Listener errors never clear `isLoading`.** `FirestoreService.swift:42-45` and three
  siblings `return` on error without calling the completion handler. Every view model
  initialises `isLoading = true` and only clears it inside that completion, so a
  permission-denied produces an infinite shimmer with no error and no retry.
- **`putDataAsync` sends no `StorageMetadata`** (`FirestoreService.swift:414`). `putData` does
  not infer a content type from the path, so it uploads as `application/octet-stream` while
  `storage.rules:24` requires `image/*`. If correct, **every proof photo upload 403s** and
  `ChallengeSubmissionViewModel.swift:127-131` swallows it into "Submission failed. Try
  again!" with no logging. **Unverified against a live bucket** — test before assuming.
- **`bootstrap()` blocks the UI on a server ack.** `SessionManager.swift:88` awaits
  `DataSeeder.seedIfNeeded()`, and `WriteBatch.commit()` resolves only on server
  acknowledgement, so an offline cold launch sits on the splash screen indefinitely.
- **Timeline titles are parsed off literal prefixes.** Written as `"Completed: …"` in four
  places and parsed back at `TimelineNodeView.swift:254`, even though `TimelineEvent.type`
  already exists (`Models/TimelineEvent.swift:29`). Breaks on any title containing a colon.
- **`Reward.defaultPointCost`** (`Models/Reward.swift:22-29`) is dead code that contradicts
  the seed — claims audio costs 75 where `DataSeeder` charges 50.
- **Two silent `RewardContentSheet` defects.** A text reward with no content renders the
  placeholder as if it were the real gift (`:42-45`); a `contentUrls` array with exactly one
  element falls through to the different `contentUrl` field and shows "Content loading soon"
  (`:57-62`).
- **`README.md:173-174` is wrong** — it claims a missing `GoogleService-Info.plist` "crashes
  at launch with a message pointing you here". `FirebaseApp.configure()` is called bare at
  `BirthdayQuestApp.swift:12`, so it dies on a raw Firebase assertion.

## Direction (as of 2026-08-20)

The app is being taken multi-tenant so any user can create and run their own occasion. It is
currently single-tenant in the strongest sense — no event/tenant field on any model,
`game_state/main` enforced as a singleton by `firestore.rules:55`, five hardcoded user doc
IDs — so this is a spine transplant, not a feature.

- Design: `docs/superpowers/specs/2026-08-20-multi-tenant-occasions-design.md`
- Plan for subsystem #1: `docs/superpowers/plans/2026-08-20-event-scoping-and-identity.md`

Decomposed into four subsystems; **#1 is a hard prerequisite for the rest.** Only #1 is
planned; nothing is implemented.

1. Event scoping + identity — `events/{eventId}` subcollections, anonymous auth with Apple
   linking, self-registration via invite links, `AppSession`/`EventSession` split.
2. Host authoring — the surfaces that let a host create challenges, rewards, and content
   without the Firebase console.
3. Media pipeline — upload UI, and the "server as courier, device as archive" model: media
   transits Storage, the celebrant's device persists it to Documents (riding their iCloud
   backup), the server copy is deleted once fetched.
4. Compliance — moderation, `PrivacyInfo.xcprivacy`, real bundle ID, rename, store listing.

Decisions already made and recorded in the spec: no Cloud Functions (rules carry all
enforcement); no lifecycle state machine (`isOpen` is a host toggle, `occasionDate` is for
sorting and purge anchoring only); five occasion types at launch; celebrant must install the
app, with no handover mode.
