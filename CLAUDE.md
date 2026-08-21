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
- **AuthService** — anonymous sign-in, Apple linking via `user.link(with:)` (preserves the uid,
  which matters because participants and memberships are keyed by it). Behind `AuthProviding`;
  `FirebaseAuthProvider` is the only type in *that file* touching `Auth.auth()` —
  `FirestoreService` also reads `Auth.auth().currentUser?.uid` for the calling uid.
- **FirestoreService** — All Firestore CRUD, behind the `GameBackend` protocol. Every
  *event-scoped* method takes an `eventId`; the handful that cannot are the listener teardowns,
  `createOccasion` (which returns one), `fetchMyOccasions` and `resolveInviteCode`. Uses **transactions** for reward unlocks (server-side balance re-check) and
  challenge completions (idempotency guard). Occasion creation is **two-phase** — see below.

### Key Firestore Patterns
- **Timestamps:** Always use `Timestamp(date: Date())`, never `FieldValue.serverTimestamp()` (breaks Codable)
- **GameState parsing:** Manual dictionary parsing with `NSNumber?.intValue`, NOT Codable (Int64/NSNumber mismatch)
- **Listener keys are event-scoped:** `ListenerKey.scoped(_:eventId:)`. Two view models sharing one
  key silently kill each other's listener — `AdminViewModel` uses `admin_rewards@<eventId>` for
  exactly this reason. Never call a global `removeAllListeners()` from a per-event object.
- **Occasion creation is two-phase, and must stay that way.** Firestore evaluates batched writes
  against *committed* state. Phase 1 writes the event document alone; phase 2 batches the host
  participant, `private/codes`, `state/main`, and the membership mirror. The rules gate the latter
  three on `events/{id}.hostUid` — **not** on participant membership — precisely so that batch can
  commit. Gating them on membership makes every occasion creation fail. There is a rules test
  pinning this.
- **Secrets never go on a document their audience can read.** Invite codes live at
  `events/{id}/private/codes` (host-read only) and joins compare against it with a
  rules-internal `get()`, which is **privileged** — not subject to these rules — so the joiner
  never needs read access to the thing that authorises them. Do not move a code, token or
  password onto the event document, and do not widen participant read past host-or-self:
  `participants.usedCode` is a code.
- **Event ids and invite codes are validated before any Firestore path is built.**
  `document(_:)` takes a *path*, and a malformed one (`//`, or an odd segment count from a
  stray `/`) raises an Objective-C `NSException` from the C++ core that Swift `do/catch`
  cannot intercept — the process aborts. `FirestoreService.eventRef` throws, and
  `InviteCode.normalized` / `EventID.isValid` are the gate. Never try to catch this.
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
| `events/{eventId}` | `name`, `occasionType`, `celebrantName`, `hostUid`, `occasionDate`, `isOpen`, `createdAt`. Member-readable, so it carries **no secrets** — host-only writes. |
| `events/{id}/private/codes` | `contributorCode`, `celebrantCode`. **Host-read only.** An invite code is a bearer secret and the event document is member-readable, so the codes cannot live there: a contributor could read the celebrant code, hand it to a fresh uid, and have that impostor claim celebrant and delete every gift. Joins compare against this with a rules-internal `get()`, which is privileged. The celebrant may `update` (clear `celebrantCode`) but never `read`. |
| `events/{id}/participants/{uid}` | `name`, `avatarId`, `mode` (`contributor`\|`celebrant`), `isHost`, `usedCode`. `mode` and `isHost` are separate — "host who is also the celebrant" is representable. **Read is host-or-self, not member:** `usedCode` is the code its owner presented, so a member-readable roster is the same secret leak one door along. |
| `events/{id}/challenges/{id}` | Includes secret challenges (`isSecret: true`) |
| `events/{id}/rewards/{id}` | Plus `fetchedBy: [String]?` for media purge tracking |
| `events/{id}/timeline/{id}` | Append-only by rule (`allow update, delete: if false`) |
| `events/{id}/state/main` | GameState. A legitimate singleton now that it is event-scoped. |
| `memberships/{uid}/events/{id}` | Thin mirror: `role`, `isHost`, `joinedAt`. No denormalized event name/date. Note the key is **`role`**, not `mode` — it holds a `ParticipantMode` raw value but is spelled differently from `participants.mode`, and no rule or query reads it today. |
| `inviteCodes/{CODE}` | Uniqueness reservation + code→event resolution only. `allow get` / **deny `list`** so a known code resolves but the collection cannot be enumerated. **Authorization does not flow through here** — joins are authorized against `events/{id}/private/codes`. Treat both the `kind` and the `eventId` stored here as attacker-controlled: anyone signed in can create a row, so validate the `eventId` you read back before building a path from it. |

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
- `cd BirthdayQuest && xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BirthdayQuestTests test`
  — the `cd` matters, or pass `-project BirthdayQuest/BirthdayQuest.xcodeproj`; the scheme is not
  discoverable from the repo root. **Always scope to `BirthdayQuestTests`.** A bare `test` also runs `BirthdayQuestUITests`, which
  boots a simulator and launches the app; it is slow, thrashes memory, and hangs in teardown. CI
  already passes `-skip-testing:BirthdayQuestUITests`.
- `cd firebase-tests && npm test` — the emulator rules suite. With no Cloud Functions, rules carry
  the entire enforcement burden, so this suite is not optional. Run it after any rules change.
- Run `swiftlint` from the **repo root**; from the nested source dir it misses `.swiftlint.yml` and
  reports hundreds of phantom violations.

## Dependencies (SPM)
- **Firebase SDK** — declared products are FirebaseAuth, FirebaseFirestore and FirebaseStorage;
  FirebaseCore arrives transitively. **FirebaseAuth is imported and central** — `AuthService` and
  `FirestoreService` both import it, and identity is the foundation of every security rule.
- **ConfettiSwiftUI** — Celebration animations
- Built-in: AVFoundation, AVKit, Combine

## Project Details
- Bundle ID: `com.example.birthdayquest`, `DEVELOPMENT_TEAM` is empty. Set signing in Xcode and keep that change out of commits (`skip-worktree` is no longer used).
- Deployment Target: iOS 26.0
- Source root: `BirthdayQuest/BirthdayQuest/` (nested due to Xcode project structure)
- GoogleService-Info.plist is gitignored — each developer needs their own Firebase project. Because
  the source dir uses folder-synced groups, **dropping it into `BirthdayQuest/BirthdayQuest/` is all
  that is needed** — no Xcode configuration. But there is no explicit pbxproj file reference, so its
  absence is not a build error: the app builds fine and then dies at launch on a raw Firebase
  assertion from the bare `FirebaseApp.configure()`, with no message pointing anywhere.
- `BirthdayQuest/Info.plist` exists **only** to carry `CFBundleURLTypes`, which registers the
  `birthdayquest://` scheme so shared invite links open the app. `CFBundleURLTypes` is an array of
  dictionaries and so cannot be an `INFOPLIST_KEY_*` build setting. It lives at SOURCE_ROOT, on
  purpose: a plist inside the folder-synced group would also be added to Copy Bundle Resources and
  fail the build. `GENERATE_INFOPLIST_FILE` stays `YES`, so generated keys merge on top of it.
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
- **A new occasion is empty.** `createOccasion` writes `totalChallenges: 0, totalRewards: 0` and
  seeds no content — `DataSeeder` is gone and host authoring is subsystem #2, so the only in-app
  authoring path is a contributor writing their secret challenge. The old "13 challenges award 715
  pts, 8 rewards cost 750" figures described the deleted seeder and are not a live invariant. The
  *design* intent stands: balance a set so challenges cannot quite cover the rewards, and let the
  secret challenges close the gap.
- **The `GameState` wire parser is untested.** `FirestoreService`'s manual
  `(data[...] as? NSNumber)?.intValue` parse covers 11 field-name string literals and is reachable
  only through `FirestoreService`, which every Swift test replaces with `MockGameBackend`. A typo in
  one literal silently yields `0` for that counter forever, with no compile error and no test
  failure. `GameState` also still carries a dead `birthdayBoyId` (always `""` since R24 stopped
  writing it) and a now-unused `Codable` conformance.
- **`JoinOccasionViewModel` reaches for `FirestoreErrorDomain` directly.** It is the one deliberate
  exception to the `GameBackend` seam: offline classification stays Firestore-specific. Testability
  is unaffected — all its tests drive it through `MockGameBackend`.
- **Accessibility is the largest unowned risk.** There is no Dynamic Type support anywhere: all 11
  `BQDesign.Typography` tokens are fixed `Font.system(size:)`, and there are ~84 further ad-hoc
  `.system(size:)` call sites outside `DesignSystem.swift`, so the token indirection does *not* give
  a single-point fix. Zero `accessibilityReduceMotion` handling against **17** `repeatForever`
  animations across 11 files. Two palette tokens fail WCAG AA for body text on white:
  `Colors.error` at 3.83:1 and `textSecondary` at 3.34:1. Dark mode is pinned off
  (`.preferredColorScheme(.light)`) because every colour is a fixed hex with no dark variant — a
  real dark theme means dark variants for every token.
- **Reward and proof media are reachable by anyone holding the URL.** The Storage rules gate the
  *objects* on event membership, but the app stores long-lived Firebase **download URLs**
  (`?alt=media&token=…`) in Firestore, and those bypass Storage rules by design. So revoking
  membership does not revoke media already linked. The spec claims the new rules replace
  world-readable URLs; they do not, and closing it needs the Plan 2 media pipeline.

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

**Also fixed, in the final whole-branch review** — these were deferred to "Plan 2" on the
assumption they needed the media pipeline. They did not:
- Both `RewardContentSheet` defects. The one-image case was a branch-selection bug
  (`contentUrls.count > 1` falling through to the unrelated `contentUrl` field), and the empty-text
  case was `contentText ?? placeholder` treating `""` as present. Branch selection is now a pure
  `RewardContentPresentation` enum with tests.
- `README.md`, plus `SECURITY.md`, `CONTRIBUTING.md` and the bug-report template.

## Direction (as of 2026-08-21)

The app is multi-tenant. Subsystem #1 (event scoping + identity) is **complete — all 16 tasks, plus
the final whole-branch review and its remediation — and merged into `main`** (fast-forward, so
history stays linear and every commit survives). **`main` is not pushed**; `origin/main` is well
behind, and the three manual steps below are why publishing was left as a deliberate decision
rather than a formality.
Build green, **142 Swift test cases + 113 emulator rules tests** passing, SwiftLint clean across 58
files. (Both counts were verified on the merged `main`. Note `xcodebuild`'s "passed on" line count
runs higher than the number of distinct tests, because parameterized cases report once per
argument — count unique test names if you need to compare.)

- Design: `docs/superpowers/specs/2026-08-20-multi-tenant-occasions-design.md`
- Plan: `docs/superpowers/plans/2026-08-20-event-scoping-and-identity.md`
- **Execution record: `.superpowers/sdd/2026-08-20-event-scoping-and-identity/`** (git-ignored)
  holds `rulings.md` — 68 decisions taken against the plan, each with what it costs if wrong — and
  `progress.md`, which carries the full session record and a ranked follow-up list. **Read
  `rulings.md` before touching this subsystem**; the plan alone is misleading in ~15 places where a
  ruling overrode it. Note R62–R68 came from the final review and *supersede* earlier rulings —
  R62 in particular overturns R35's mechanism.

**The final review found four Criticals, all fixed.** Every one spanned a boundary no single task
owned, which is why 21 clean per-task reviews missed them — worth remembering before trusting
per-task review alone on the next subsystem:
1. **Celebrant privilege escalation.** The event document was member-readable and carried both
   invite codes, so any contributor could harvest the celebrant code and have a fresh uid claim
   celebrant — then delete every gift and proof photo, irreversibly. Codes moved to
   `events/{id}/private/codes`; participant reads narrowed to host-or-self for the same reason.
2. **An uncatchable crash on the primary join path.** `document(_:)` takes a path, and the
   Objective-C exception it raises on a malformed one cannot be caught in Swift. Pasting an invite
   URL into the code field — the documented workaround — aborted the process.
3. **`birthdayquest://` was registered nowhere**, so every shared invite link was inert. A mandated
   plan step that was silently skipped.
4. **Listener failures set a message no view rendered**, so a revoked member saw a cheerful empty
   state, with a green test asserting the opposite.

**Manual steps required before any of this works against a live project** — none are detectable by
any test, so a fully green suite proves nothing about a live project:
1. Xcode: add the **Sign in with Apple** capability. The UI now exists and will fail at runtime
   without it.
2. Firebase console: enable the **Anonymous** and **Apple** providers. Anonymous gates *everything*
   — without it the app cannot get past launch. Apple gates only the linking path.
3. Run `tools/export_media.sh` **before** `firebase deploy` — the new rules deny all access to the
   old `rewards/**` and `proofs/**` prefixes.

Remaining subsystems, unchanged: #2 host authoring (the 39-item gap list), #3 media pipeline
(`MediaStore`, server-as-courier), #4 compliance (moderation, `PrivacyInfo.xcprivacy`, real bundle
ID, rename away from "BirthdayQuest", store listing).

Decisions already made and still binding: no Cloud Functions (rules carry all enforcement); no
lifecycle state machine (`isOpen` is a host toggle, `occasionDate` is for sorting and purge
anchoring only); five occasion types at launch; celebrant must install the app, with **no handover
mode** — which is why the host panel surfaces celebrant-not-joined prominently.
