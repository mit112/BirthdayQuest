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
- **GameState parsing:** Manual dictionary parsing with `NSNumber?.intValue`, NOT Codable
  (Int64/NSNumber mismatch). It lives in `GameState.init(wire:)` behind a `WireKey` namespace, not
  in `FirestoreService` — that put the field-name literals inside the one type every Swift test
  mocks out. `GameState` deliberately has **no `Codable` conformance**: it was unused and it
  invited `data(as:)`, which is the exact trap the manual parse exists to avoid. Note a boolean
  may arrive as `NSNumber`, and `as? Bool` correctly accepts it — a stricter cast would read
  `finalBadgeUnlocked` as `false` forever and the final celebration would never fire.
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
- **A single `updateData` on `challenges`/`rewards` must not mix content and gameplay keys.** The
  rules reject a write whose changed keys span two tiers, and it fails only at runtime, as
  permission-denied — nothing catches this at compile time.

### Design System
All UI tokens live in `DesignSystem.swift` under the `BQDesign` namespace (colors, typography, spacing, radius, shadows, animations). Use these instead of hardcoded values.

Three invariants now hold there, and all are easy to break by accident:
- **Every typography token is a semantic text style, never `Font.system(size:)`.** A fixed size
  ignores the user's content size category and they cannot override it. For a glyph — an SF Symbol
  or a decorative emoji — use `@ScaledMetric` instead, which scales a *dimension*; do not reach for
  a fixed size just because the thing is not prose.
- **Perpetual animation is gated in exactly one place.** `MotionLevel`, read via
  `@Environment(\.bqMotionLevel)`, resolves a fixed one-way order: Reduce Motion wins outright,
  Low Power Mode only gets a vote if it passed. Ask `allowsPerpetual`; never re-derive the rule and
  never read `accessibilityReduceMotion` directly. For an imperative `withAnimation`, *guard* it —
  passing a nil animation snaps the flag to its animated end value and leaves the view stuck in the
  "on" pose. One-shot entrance animations are out of scope and stay ungated.
- **The palette records its own contrast ratios.** `textTertiary`, `gold` and `success` are not
  text colours on a light surface; `goldText` exists for exactly that case. Check the comment on a
  token before putting a sentence in it.
- **Every token is scheme-adaptive; there is no light-only escape hatch.** Dark mode shipped
  2026-08-28 (`.preferredColorScheme(.light)` is gone). Each `BQDesign` color is built via a
  private `adaptive(light:dark:)` helper over `Color(uiColor: UIColor { traits in ... })`, taking
  `0xRRGGBB` pairs — a typo is a compile error, unlike `Color(hex:)`, which silently falls back to
  black. Static-let gradients adapt for free because the provider resolves at *draw* time, not at
  declaration. Light values are unchanged byte-for-byte from before dark mode, so every previously
  recorded light ratio still holds. `PaletteContrastTests` asserts AA floors against the
  **resolved** `UIColor` in both appearances, not a parallel constant table — that is what makes
  the test non-vacuous. Two things are deliberately scheme-invariant, and a naive "convert every
  hardcoded colour" pass would break both: the spy-dossier surfaces (`secretDark`/`secretDeep`)
  stay dark in *both* appearances (their ~30 `Color.white` glyph sites are correct as written, and
  the surfaces earn separation from the page by lightness, not by contrast with a light
  background), and white text on a saturated brand gradient is likewise scheme-invariant because
  the gradient itself is. A page gradient or card surface is authored as a low-opacity brand tint
  **over** a surface token — never as its own fixed hex — with the opacity solved against the hex
  it replaced so light still resolves within a few 255ths; end stops use a brand token at zero
  alpha, never `.clear` (`.clear` is transparent *black*, and SwiftUI interpolates neighbours
  through it, which shows up as a visible dark fringe). A locked reward card recedes *below*
  `cardBackground` in both schemes now, not just in light.
  Known remaining, not regressions: `Challenge.difficulty.color` is a model-supplied hex string
  and is not adaptive (accepted — difficulty is carried by star count, so colour is never the only
  signal); the audio scrub thumb stays `Color.white` to match `UISlider` and fails WCAG 1.4.11
  against the unfilled track in light (1.10:1, pre-existing, not introduced by dark mode);
  `textSecondary` on the timeline page's deepest gradient stop is 4.05:1 in light, still under AA
  but better than the 3.96:1 it replaced.

### Collections
All event content lives under `events/{eventId}` subcollections. Isolation is by **path**, not by
query discipline — a client cannot express a query reaching another occasion, because the path does
not exist for them. Never reintroduce a root-level content collection.

| Path | Notes |
|---|---|
| `events/{eventId}` | `name`, `occasionType`, `celebrantName`, `hostUid`, `occasionDate`, `isOpen`, `createdAt`. Member-readable, so it carries **no secrets** — host-only writes. |
| `events/{id}/private/codes` | `contributorCode`, `celebrantCode`. **Host-read only.** An invite code is a bearer secret and the event document is member-readable, so the codes cannot live there: a contributor could read the celebrant code, hand it to a fresh uid, and have that impostor claim celebrant and delete every gift. Joins compare against this with a rules-internal `get()`, which is privileged. The celebrant may `update` (clear `celebrantCode`) but never `read`. |
| `events/{id}/participants/{uid}` | `name`, `avatarId`, `mode` (`contributor`\|`celebrant`), `isHost`, `usedCode`. `mode` and `isHost` are separate — "host who is also the celebrant" is representable. **Read is host-or-self, not member:** `usedCode` is the code its owner presented, so a member-readable roster is the same secret leak one door along. **Delete is host-or-self** (2026-08-28): the host ejecting a contributor, or a member deleting their own document — the latter is what in-app account deletion (`deleteMyAccountData`) is built on, since this document is where a uid's name, avatar and `usedCode` live. The self clause is not conditioned on role, so a host can delete their own account too; the accepted cost is an occasion left with no host, since `isHost()` reads this document and host transfer is not a feature. |
| `events/{id}/challenges/{id}` | Includes secret challenges (`isSecret: true`). `update` is field-scoped: gameplay fields (e.g. `isCompleted`, `proofUrl`) are member-writable, content fields (`title`, `pointValue`, etc.) are host-or-author, and `isSecret`/`createdByUserId`/`createdAt` are immutable by omission from every allow-list. |
| `events/{id}/rewards/{id}` | Plus `fetchedBy: [String]?` for media purge tracking. `update` is field-scoped the same way: gameplay fields are member-writable, content fields are host-or-author, `pointCost`/`sortOrder` are host-only, and `fromUserId`/`createdAt` are immutable by omission. |
| `events/{id}/timeline/{id}` | Append-only by rule (`allow update, delete: if false`) |
| `events/{id}/state/main` | GameState. A legitimate singleton now that it is event-scoped. |
| `events/{id}/reports/{id}` | Content reports (App Store 1.2). `{ contentType (`reward`\|`challenge`), contentId, reportedByUserId (==auth.uid), reason?, createdAt }`. **Member-create, host-read only** (the reporter's uid is host-moderation-scoped), append-only (`update, delete: if false`). Mutation-proven. |
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
  assertion from the bare `FirebaseApp.configure()`, with no message pointing anywhere. The
  development copy's `BUNDLE_ID` is `com.yourname.birthdayquest`, which does not match
  `PRODUCT_BUNDLE_IDENTIFIER` (`com.example.birthdayquest`) — harmless for Firebase (it does not
  gate on bundle ID for Auth/Firestore/Storage the way it does for push), but worth fixing when the
  real bundle ID is assigned so the two stop disagreeing.
- `BirthdayQuest/Info.plist` exists **only** to carry `CFBundleURLTypes`, which registers the
  `birthdayquest://` scheme so shared invite links open the app. `CFBundleURLTypes` is an array of
  dictionaries and so cannot be an `INFOPLIST_KEY_*` build setting. It lives at SOURCE_ROOT, on
  purpose: a plist inside the folder-synced group would also be added to Copy Bundle Resources and
  fail the build. `GENERATE_INFOPLIST_FILE` stays `YES`, so generated keys merge on top of it. It
  also now carries `ITSAppUsesNonExemptEncryption = false` (2026-08-28) — the app uses only
  HTTPS/TLS via the Firebase SDKs and CryptoKit SHA-256 for the Apple sign-in nonce, both exempt
  categories, so answering it here avoids the export-compliance prompt on every upload.
- `BirthdayQuest/BirthdayQuest.entitlements` (2026-08-28) sits at SOURCE_ROOT beside `Info.plist`,
  not inside the folder-synced group, for the same Copy-Bundle-Resources reason. Unlike
  `CFBundleURLTypes`, `CODE_SIGN_ENTITLEMENTS` **is** a plain string, so it is safe to add directly
  to the app target's two pbxproj config blocks as a build setting — the same precedent as
  `INFOPLIST_KEY_NSMicrophoneUsageDescription`. It is what actually wires the Sign in with Apple
  capability: the UI (`SignInWithAppleButton`, `ASAuthorizationAppleIDRequest`) existed since the
  identity work, but with no entitlements file and no `CODE_SIGN_ENTITLEMENTS` setting the
  capability was never configured and the flow failed at runtime.
- Security rules live in `firestore.rules` / `storage.rules`, deployed via `firebase deploy --only firestore:rules,storage`.

## Known Gaps (do not "discover" these as new)
- ~~The atomic transaction logic (`unlockRewardAtomically`, `completeChallengeAtomically`,
  `adminForceUnlockReward`) is NOT covered by tests.~~ **Closed (2026-08-25).** An emulator-backed
  harness now proves it: `FirestoreService` gained an injectable `init(db:)`, and
  `BirthdayQuestTests/TransactionIntegrationTests` seeds docs via a secondary emulator-pointed
  `FirebaseApp` and runs the *real* methods against the Firestore emulator — a short balance is
  refused and writes nothing (the balance re-check), a double-submit awards once (the idempotency
  guard). The suite is gated on `EmulatorProbe.isReachable` (a socket probe to :8080), so the
  normal `-only-testing:BirthdayQuestTests` pass **skips** it (verified: the four cases report
  `skipped`); a dedicated CI job runs it wrapped in `firebase emulators:exec` against the **open**
  rules in `integration-tests/` (authorization is out of scope here — the 183-test rules suite owns
  it). Both guards were proven **non-vacuous**: with each guard defeated, its test fails. See
  `integration-tests/README.md` and `docs/superpowers/specs/2026-08-25-transaction-harness-feasibility.md`.
- **Any member can rewrite `state/main` (point balances) and flip `rewards.isUnlocked`.** The rules
  gate those on membership only. This is the pre-existing no-Functions trust model, not a
  regression — but it is now a stranger-facing assumption rather than a family one. The same gap
  reaches reward *create*, too: `create` does not constrain `isUnlocked`/`unlockedAt`, so a member
  creating their own gift could set it already unlocked. Not a separate hole — the update gameplay
  tier already lets any member flip `isUnlocked` on any reward, so closing create alone would be
  decorative.
- Accessibility: Dynamic Type, Reduce Motion and AA contrast are now handled (see the Design
  System section). Visual confirmation of reflow at the largest accessibility sizes is **partially
  done, not closed** — no snapshot tests exist and the unit suite cannot catch clipping or overlap.
  `xcrun simctl ui booted content_size accessibility-extra-extra-extra-large` is the command; it
  needs a live Firebase project, because the app cannot get past launch without the Anonymous
  provider. Spot-checked 2026-08-28 on iPhone 17 Pro Max at that size: launch and the empty/failure
  states (`EmptyOccasionsView`) reflow correctly, no clipping or overlap. **Not yet checked:**
  `AccountView` and `TermsView` — no UI-automation tap was available in that session, and a system
  "Open in?" dialog blocks deep-linked navigation to them. Do not read "spot-checked" as "all
  screens verified."
- `fetchMyOccasions` fans out **concurrently** (`withTaskGroup`, `@MainActor` children so nothing
  crosses an isolation boundary). Its **skip-on-failure is load-bearing and has no test**: each
  child returns `Occasion?` and never throws, so a membership naming a deleted event is skipped
  rather than failing the whole list. No test is possible while every Swift test substitutes
  `MockGameBackend` for `FirestoreService`, so do not "tidy" that optional into a `throws`.
- The 3 `BirthdayQuestUITests` are Xcode template boilerplate (`testExample`, `testLaunch`,
  `testLaunchPerformance`) — **not** character-select tests, contrary to the earlier note here
  (verified 2026-08-25). They compile and are CI-skipped (`-skip-testing:BirthdayQuestUITests`). Real
  UI-flow tests need a live Firebase project (the app cannot pass launch without the Anonymous
  provider), so they stay boilerplate until that exists — there is no "dead" flow to rewrite.
- **A new occasion starts empty, but is no longer stuck that way.** `createOccasion` still writes
  `totalChallenges: 0, totalRewards: 0` and seeds no content, but subsystem #2 slice 1 gave it two
  in-app authoring paths: the host authors challenges (`ChallengeAuthoringView`), and each
  contributor authors one text gift (`GiftAuthoringView`); the host then prices, orders, and can
  delete gifts (`GiftCurationView`) without being able to rewrite their text. `totalChallenges` /
  `totalRewards` now move with the content, batched inside `FirestoreService`. **Subsystem #3 slice 1
  (as of 2026-08-24) added photo gifts**: `GiftAuthoringView` gained a Letter/Photos selector, a
  contributor uploads images via `FirestoreService.uploadRewardMedia` (which returns the Storage
  object *path*, never a download URL), and a new `MediaStore` actor downloads+persists them to
  Documents and hands the celebrant a local `file://` URL to render. **Subsystem #3 slice 2 (as of
  2026-08-24) added video gifts**: `GiftAuthoringView`'s selector gained a Video option, a
  contributor picks a clip via `PhotosPicker(matching: .videos)`, it uploads with contentType
  `video/mp4`/`video/quicktime` and writes `contentType: .video` + the single `contentUrl` (never
  `contentUrls`). The whole celebrant/playback half was already built in slice 1
  (`RewardContentPresentation.resolve`, `MediaStore.storagePaths`, `VideoPlayerView`), so slice 2
  was purely contributor-side authoring and needed no rules change. **Subsystem #3 slice 3 (as of
  2026-08-24) added audio/voice gifts**: `GiftAuthoringView`'s selector gained a Voice option with TWO
  input paths — record (`AudioRecorderController` → AVAudioRecorder AAC/.m4a, 5-min cap,
  `NSMicrophoneUsageDescription` build setting, `.playAndRecord` scoped to the recording lifecycle) and
  import (`.fileImporter([.mpeg4Audio, .mp3])`) — plus a review-before-save replay through
  `AudioPlayerController`; it writes `contentType: .audio` + the single `contentUrl` (never
  `contentUrls`). No rules change (the spine already accepted `audio/*`). The old "13 challenges award
  715 pts, 8 rewards cost
  750" figures described the deleted seeder and are not a live invariant. The *design* intent
  stands: balance a set so challenges cannot quite cover the rewards, and let the secret challenges
  close the gap.
- ~~The `GameState` wire parser is untested.~~ **Closed.** Extracted to `GameState.init(wire:)`
  and covered by `GameStateWireTests`; `birthdayBoyId` and the unused `Codable` conformance are
  gone. Each key is asserted twice — that it reaches its own field, *and* that removing it changes
  the parse. Keep the second assertion in any new key: a test reading a fully-populated document
  passes just as happily against a parser that never mentions the key, since the expected value and
  the fallback coincide. That is why the original bug was invisible.
- **`JoinOccasionViewModel` reaches for `FirestoreErrorDomain` directly.** It is the one deliberate
  exception to the `GameBackend` seam: offline classification stays Firestore-specific. Testability
  is unaffected — all its tests drive it through `MockGameBackend`.
- ~~Accessibility is the largest unowned risk.~~ **Largely closed.** All 11 typography tokens are
  semantic text styles, all 87 ad-hoc `.system(size:)` call sites are converted, all 17
  `repeatForever` animations are gated, and no text sits on a token that fails AA. Two things
  remain: **reflow is visually unverified** (above), and a correction worth keeping — the earlier
  claim that "two palette tokens fail AA" was measured against **white**, but the app background is
  `#FBF7F4`, and against it **seven of nine** text-capable tokens failed. `textTertiary` was the
  significant one at 1.88:1, carrying real text in ~8 places including an error message and the
  timeline empty state. It is still deliberately light, because that is what makes it right for a
  15%-opacity skeleton fill — its *text* uses moved to `textSecondary`. `Colors.error` at 3.59:1 is
  unchanged and still large-text-only: the error rows put the colour on an icon and leave the
  sentence at `textPrimary`, and that split is the pattern to copy.
  ~~Dark mode is still pinned off (`.preferredColorScheme(.light)`)~~ **Shipped (2026-08-28,
  `3a25004`).** See the Design System section for the mechanism. The old warning that darkening
  `textSecondary` lowered its contrast on the dark secret surfaces (5.11:1 → 3.18:1) is now
  **resolved** there (5.26:1 in dark), because those surfaces stay dark in both appearances by
  design; the light-mode figure it was measured against is unchanged and the underlying
  prohibition (don't darken `textSecondary` without re-checking every surface it lands on) still
  stands — this is a correction to the note, not a deletion of it. Visually confirmed in the
  simulator at 1320×2868.
- **Reward-media leak, reward-media LIFECYCLE, and the proof-photo leak are all CLOSED (merged to
  main 2026-08-25).** Subsystem #3 slice 1 closed the reward-media leak: `rewards.contentUrl`/
  `contentUrls` store Storage **object paths**, and `MediaStore` downloads them through an
  authenticated `Storage.storage().reference(withPath:)` (honouring the Storage rules) into a local
  `file://` URL — no tokened download URL is ever persisted for a reward.
  - **Media-lifecycle slice — DONE.** `MediaLifecycle` (pure policy: `occasionDate + gracePeriod`,
    30-day grace / 7-day reminder window, `now` always injected) drives three things: (1) celebrant-
    only server purge (`MediaStore.purgeExpiredArchived`, fired once per rewards-view appearance),
    gated on **archive-before-purge** — it deletes a reward's Storage objects only when EVERY local
    file is on disk *right now* (never trusting `fetchedBy`), so it can never delete the celebrant's
    last copy (pinned by a mutation-proven test); (2) a distinct `RewardContentPresentation.expired`
    state (from a Storage objectNotFound with no local archive — honest copy, no confetti), separate
    from `.unavailable` ("never authored"); (3) a dismissible expiry-reminder banner when unopened
    media gifts are near expiry. No rules change (celebrant Storage delete was already granted).
    ~~Still deferred: the full re-send round-trip … streaming/file-URL upload, and thumbnail
    previews in the "selected" rows.~~ **Re-send round-trip CLOSED (`53c3e7e`, 2026-08-28).** A
    contributor can now re-send a gift whose media expired — see the dedicated Known Gap entry
    below for the mechanism and the new invariant it establishes. Video and audio "selected" rows
    also gained a poster frame and a duration display respectively, closing the thumbnail-preview
    deferral. **Still open:** streaming/file-URL upload (the ≤200MB clip still loads fully into
    memory via `Data(contentsOf:)` before upload — an API change, not a slice change).
  - **Proof-photo leak — CLOSED.** `uploadProofData` now returns the Storage **path** (not a tokened
    download URL); `challenge.proofUrl` holds a path; a new `ProofImageView` renders it via
    `MediaStore.localURL(forPath:eventId:)` (a narrow `ProofMediaLoading` protocol — authenticated
    download → local `file://`). A revoked member is now denied by the Storage rules. No rules change.
    ~~Still deferred: proof-media purge/expiry~~ **CLOSED (`caf1864`, 2026-08-28).** See the
    dedicated Known Gap entry below.
  - The host *can* delete reward-media objects during curation (`storage.rules` delete widened to
    `isCelebrant || isHost`).
- **Gift re-send after expiry (`53c3e7e`, 2026-08-28) — CLOSED.** `isEditable` on
  `GiftAuthoringViewModel` is unchanged (still `!(existingGift?.isUnlocked ?? false)`); two derived
  flags, `canAttachMedia` and `isResendOnly`, carve out media-only editing on an otherwise-frozen
  gift. Detection is two-stage: `MediaLifecycle`'s date test gates whether any network call happens
  at all (keeps live occasions free of probing), then a narrow injectable `RewardMediaProbing` seam
  — deliberately **not** a `GameBackend` method, since that seam is Firestore CRUD plus uploads and
  this is a Storage **metadata** read with different failure semantics — checks each stored path.
  The probe **fails closed**: only a confirmed `objectNotFound` counts as expired; present,
  unauthorized and offline all answer "not expired," because a wrong "present" only preserves
  today's behaviour while a wrong "gone" would hand out a rewrite. **Invariant worth its own
  line:** a re-send writes *only* `contentUrl`/`contentUrls`. It must never grow to include
  `title`/`teaser`/letter text — those sit in the same content tier, so the rules would accept
  them, and the payload construction is the only thing stopping a contributor from rewriting a
  gift the celebrant already read. This is a code-level guarantee, not a rules-level one; do not
  assume the rules would catch a regression here. No rules change; `RewardContentPresentation.resolve`
  needed none either, because `uploadRewardMedia` mints a fresh UUID filename and `MediaStore` keys
  its cache on `lastPathComponent`, so new media is a guaranteed cache miss.
- **Proof-photo expiry (`caf1864`, 2026-08-28) — CLOSED.** New `ProofMediaPurging` protocol +
  `MediaStore.purgeExpiredProofs`, fired from `ChallengesBoardView` via
  `ChallengesViewModel.runProofMediaLifecycle`, mirroring the rewards trigger. No rules change —
  proof delete was already celebrant-only, and it stays that way on purpose: the host got
  reward-media delete because curation deletes gifts and must take their Storage objects along,
  but the host moderates a challenge by deleting the *document*, so widening proof delete to the
  host would only add a way to destroy a contributor's evidence before the celebrant ever sees it.
  **Archive-before-purge is deliberately NOT copied from rewards, and a test pins the omission so
  it isn't re-added by reflex:** a gift is an irreplaceable keepsake whose server copy may be the
  only one; a proof is transient evidence, and everything durable about it (`isCompleted`,
  `completedAt`, the points awarded, the timeline entry) lives in Firestore, untouched by this
  sweep. Copying the reward gate would also invert the intent — proofs are only downloaded when
  someone opens that one challenge, so most are never archived on the celebrant's device, and
  "only purge what's already archived" would spare exactly the objects the sweep exists to
  reclaim. **The security guard that replaces it is the important part.** `challenge.proofUrl` is
  in the gameplay tier, so any member can write it to any string, and the celebrant is authorised
  to delete both proof objects and reward media in their own event. A contributor could write
  another contributor's *gift* path into `proofUrl` and have the celebrant's own sweep destroy
  that gift — the Storage rules cannot object, because both deletes are legitimately the
  celebrant's to make. The sweep defends against this by rebuilding the expected path with the
  same `StoragePaths.proof(...)` constructor the upload uses and requiring exact equality before
  deleting anything. Mutation-proven by three tests. A purged proof now presents as `.expired`
  ("isn't kept anymore") via a new `ProofImagePresentation` enum, rather than as a load failure.
  **Latent gap, not closed by this commit:** deleting a challenge (host moderation,
  `FirestoreService.deleteChallenge`) does not delete its proof Storage object. The sweep only
  iterates *live* challenges, so a proof orphaned by challenge deletion is unreachable forever.
  Closing it needs either a purge-on-delete with a host-side Storage grant (a `storage.rules`
  change) or a decision to accept the orphan.
- **`validRewardContent()` reward-media path binding — CLOSED (2026-08-30).** A reward's media must
  now live under that gift's **own** Storage folder, `events/{eventId}/rewards/{rewardId}/…`.
  `validRewardContent(eventId, rewardId)` (was arg-less) calls a new `rewardMediaScoped` that pins
  `contentUrl` and every `contentUrls[i]` to a `events/{eventId}/rewards/{rewardId}/` prefix (via a
  string-slice `hasStoragePrefix`, injection-safe — no regex built from data). This required an
  **authoring restructure**, because the media used to upload into a random-UUID folder unrelated to
  the doc: `GiftAuthoringViewModel` now derives `rewardId = existingGift?.id ?? UUID().uuidString`
  and uses it as **both** the upload folder and the created doc id (a UUID is a valid Firestore doc
  id), and `createReward` gained a `rewardId:` param (uses `.document(rewardId)`). Enforced on create
  **and** update, mutation-proven — neutering `rewardMediaScoped` reddens exactly the three
  foreign-path denial tests while the three own-folder allowances stay green. **Known limit of the
  rules layer:** Firestore rules cannot iterate an arbitrary list, so `contentUrls` is capped at the
  app's photo limit (`maxPhotoCount = 10`) and each slot index-checked — a gallery over 10 would be
  denied, which the app never produces. Bounded to one occasion regardless (cross-event paths already
  403 at Storage read time); this closes the same-occasion cross-gift spoof + purge-collateral.

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

## Direction (as of 2026-08-28)

Eight commits landed on `main` (linear). The first five close the remaining App Store compliance
surface and correct two stale claims in this file; the last three (below) close the two remaining
media deferrals and ship dark mode. **`main` is now pushed** — `origin/main` matches local `main`
at `3a25004` (`git rev-list --count origin/main..main` is 0).

- **Sign in with Apple entitlement + encryption exemption (`839cf96`).** New
  `BirthdayQuest/BirthdayQuest.entitlements` + `CODE_SIGN_ENTITLEMENTS` on the app target +
  `ITSAppUsesNonExemptEncryption = false`. See Project Details for the mechanics; the takeaway
  worth keeping is that a plain-string build setting (`CODE_SIGN_ENTITLEMENTS`, like
  `INFOPLIST_KEY_NSMicrophoneUsageDescription` before it) is safe to add to the pbxproj — it is
  specifically array-valued keys like `CFBundleURLTypes` that are not.
- **In-app Terms of Use, App Store Guideline 1.2 (`c106bf2`).** New `Models/LegalCopy.swift` (a
  titled-section enum, not one string, so each heading can be marked for VoiceOver) and
  `Views/Profile/TermsView.swift`. `Views/Profile/TermsAgreementSection.swift` sits on **both**
  `CreateOccasionView` and `JoinOccasionView` — 1.2 wants agreement at the point of the act, not
  merely reachable terms. The retention section deliberately does not promise media is deleted at
  30 days: `purgeExpiredArchived` is celebrant-device-driven and gated on archive-before-purge, so
  30 days is only when server media becomes *eligible* for cleanup. Anyone editing that copy has to
  keep it consistent with `MediaLifecycle`. Support email and privacy-policy URL are explicit
  `REPLACE_WITH_*` placeholders — still human-gated, see below.
- **In-app account deletion, App Store Guideline 5.1.1(v) (`d2b64b7`).** Policy is
  anonymise-and-keep: the participant document (name, avatar, `usedCode`) and every membership
  mirror row are deleted; authored gifts, dares and timeline entries stay, so a celebrant never
  loses a present because the sender closed their account. **Ordering is load-bearing:** Firestore
  data first, auth user last — every rule is written against `request.auth.uid`, so a document
  still naming a deleted uid becomes unreachable and undeletable by anyone afterwards, including its
  own owner. `deleteMyAccountData` therefore uses a **throwing** task group, the deliberate
  inversion of `fetchMyOccasions`'s skip-on-failure documented above — the first failure has to
  propagate so the account stays intact and retryable, and a partial re-issue is safe because
  deleting an absent document succeeds. `firestore.rules` widens the `participants` delete rule
  from host-only to host-or-self (see the Collections table); mutation-proven, and a second
  mutation confirms swapping the two deletion calls reddens exactly the three order-sensitive
  tests. Known consequence, accepted rather than solved: a host who deletes their account orphans
  the occasion, since `isHost` reads the participant doc and host transfer is not a feature — the
  confirmation names affected occasions before the fact, since there's no discovering it after.
  `AccountView` is deliberately **not** part of `ProfileView` (which is occasion-scoped, takes an
  `eventId`) — it hangs off both `OccasionListView` and `EmptyOccasionsView` instead, so it stays
  reachable for someone with no occasions to open, the person likeliest to want to close their
  account.
- **README + SECURITY.md corrections (`8113b0d`).** README no longer claims media gifts are
  unauthorable, no longer lists invite codes as fields on the event document (fixed as a Critical
  in subsystem #1 — the event doc is member-readable), and no longer calls the transactions
  untested. SECURITY.md no longer warns that reward-media URLs are public links (closed by the
  media-pipeline slices) and now discloses the gap that actually stands: any member can rewrite
  `state/main` and flip `rewards.isUnlocked` (already tracked above in Known Gaps; it just wasn't
  in the public security doc before).
- **Privacy manifest merged (`b3f9ccc`) — and the "one-click Xcode step" claim was wrong.**
  `feat/privacy-manifest` (authored 2026-08-25) is rebased and fast-forwarded into `main`; there
  are no unmerged branches left. More importantly, **the manual Target Membership step this file
  and the spec both described never had to happen.** Measured on 2026-08-28: a plain `xcodebuild`
  bundles `PrivacyInfo.xcprivacy` at the app root, byte-identical to source (md5 match), in **both**
  Debug and Release, with no pbxproj entry at all. The earlier "sync auto-adds `.xcassets` but not
  `.xcprivacy`" observation does not reproduce and was most likely taken against a tree where the
  file only existed on the unmerged branch. `docs/superpowers/specs/2026-08-25-privacy-manifest.md`
  has already been corrected with the two-command check to re-run if this is ever doubted again —
  don't re-add the manual step on the strength of the old note.
- **Gift re-send after media expiry (`53c3e7e`).** Closes the re-send-round-trip deferral from the
  media-lifecycle slice. See the dedicated Known Gap entry above for the mechanism (two-stage
  detection, fail-closed probe) and the invariant it establishes (a re-send writes only
  `contentUrl`/`contentUrls`, never the content-tier text fields — enforced by the payload, not
  the rules). Also closes the thumbnail-preview deferral: the video row gained a poster frame and
  the voice row a duration display.
- **Proof-photo expiry (`caf1864`).** Closes the proof-media purge/expiry deferral. See the
  dedicated Known Gap entry above for why archive-before-purge was deliberately *not* copied from
  the reward sweep, and for the path-equality guard that stops a contributor from aiming the
  celebrant's own sweep at another contributor's gift. Surfaces one new latent gap (also recorded
  above): deleting a challenge does not delete its proof object.
- **Dark mode (`3a25004`).** `.preferredColorScheme(.light)` is gone; every `BQDesign` token is
  scheme-adaptive. See the Design System section for the mechanism and the two deliberately
  scheme-invariant surfaces, and the Known Gaps accessibility entry for the corrected
  `textSecondary` contrast note. Visually confirmed in the simulator at 1320×2868, in addition to
  the new `PaletteContrastTests` suite (resolved-`UIColor` assertions in both appearances).

**Also verified today, running the app against the live project (`birthdayquest-90578`):**
anonymous auth works, but `fetchMyOccasions` fails with `Missing or insufficient permissions`. The
cause is not a code bug: the live project is still running rules that predate the event-scoping
migration (subsystem #1), so `firebase deploy --only firestore:rules,storage` was never run against
it. This sharpens the standing "manual steps" list below — the live-project blocker right now is
undeployed rules, not the auth providers, which are already enabled and working.

**Verification baseline, re-run on the final tree (through `3a25004`), real exit codes:**
- Swift unit suite: exit 0, `** TEST SUCCEEDED **`, 389 test-case passes (count test cases with
  `xcodebuild ... | grep -c "Test Case '.*' passed"` rather than trusting this number stale).
- Emulator rules suite: **not** re-run for these last three commits, deliberately — no rules file
  was touched, and this project gates that suite on rules changes (still 187/187 from the prior
  entry — `grep -c '^\s*it(' firebase-tests/*.test.js` for the live count).
- SwiftLint `--strict`: 0 violations, 78 files.
- Dark mode also visually confirmed in the simulator at 1320×2868.

**The "Genuinely NOT done" human-gated list, corrected:** the Xcode target-membership step for
`PrivacyInfo.xcprivacy` is gone (see above — it was never actually needed), and **pushing `main`
to origin is done** — `origin/main` is at `3a25004`. What remains is unchanged in kind: **Apple
Developer account** (real `DEVELOPMENT_TEAM` + bundle ID + signing, replacing
`com.example.birthdayquest`), **deploying the current rules** to the live project
(`firebase deploy --only firestore:rules,storage` — newly identified as blocking, not just
routine), the **EULA/privacy-policy placeholder values** in `LegalCopy.swift` (support email,
privacy-policy URL — product writing done, legal sign-off is not), **store listing + screenshots**,
and the **live a11y reflow check** for `AccountView`/`TermsView` specifically (above).

## Direction (as of 2026-08-25)

Session focus: close the remaining media/security work and survey #4. Landed on `main` (FF, linear;
still **unpushed**):
- **Reward-media LIFECYCLE slice (subsystem #3, final slice) — DONE + merged.** `MediaLifecycle`
  policy + celebrant `purgeExpiredArchived` (archive-before-purge, mutation-proven) + `.expired`
  presentation state + expiry-reminder banner. Reviews: correctness clean (Opus), a11y clean
  (Sonnet). No rules change. See `docs/superpowers/specs/2026-08-24-media-lifecycle-design.md`.
- **Proof-photo leak — CLOSED + merged.** Proof photos store Storage paths, render via authenticated
  download (`ProofImageView` / `ProofMediaLoading`). Security review clean (Sonnet). No rules change.
  See `docs/superpowers/specs/2026-08-25-proof-photo-paths-design.md`.

Authored on branch `feat/privacy-manifest`, and **now merged** (`b3f9ccc`, 2026-08-28 — see that
Direction entry above): the App Store `PrivacyInfo.xcprivacy`. It is valid (`plutil` OK) with
factual tracking=false + file-timestamp required-reason APIs; the `NSPrivacyCollectedDataTypes`
declaration still needs developer sign-off, but the bundling step that follows does **not** need a
human — the "one-click Xcode target-membership" requirement below was measured wrong (a plain
`xcodebuild` bundles it with no pbxproj entry, in both configurations). See
`docs/superpowers/specs/2026-08-25-privacy-manifest.md`, which has already been corrected.

Also landed on `main` this session (all FF, green, reviewed):
- **Gift-type picker → `.menu`** — 4 word-labels truncated in a segmented control at large Dynamic
  Type; a menu picker never clips. Closes the documented reflow gap for that control.
- **Host participant removal** — the host removes a contributor; deleting the participant doc revokes
  membership via the pre-existing `isHost` delete rule (no rule change; that rule was previously
  UNTESTED — now mutation-proven). Authored gifts are kept; the stale membership mirror is harmless
  (`fetchMyOccasions` skip-on-failure drops the occasion). See `2026-08-25-participant-removal-design.md`.
- **Content reporting (App Store 1.2)** — any member reports a gift **or a challenge** → a host-read
  `events/{id}/reports` collection (NEW rules, mutation-proven) → host moderates via the existing
  delete. With participant removal (the "eject an abusive user" half) this is the 1.2 mechanism; only
  the EULA text is human-gated. Gift reports flow through `RewardsViewModel.reportReward`, challenge
  reports through `ChallengeSubmissionViewModel.reportChallenge`
  (Views-don't-touch-backend); each confirmation is hosted on the sheet that presents the content, not
  on the parent, because an alert bound to the parent cannot appear over a presented sheet. See
  `2026-08-25-content-reporting-design.md`.
  - **Challenge reporting (2026-08-26)** closed the asymmetry — the backend seam, the `Report` model
    and `AdminViewModel.reportedContentTitle` were already generic, so this was a view-model method,
    the affordance, and tests. **No rules change** (`contentType in ['reward', 'challenge']` already
    allowed it) — but the rules suite only ever exercised `'reward'`, so a case pinning that
    `'challenge'` is *accepted* was added: narrowing the list to `['reward']` now reddens it instead
    of failing at runtime as permission-denied. The challenge affordance is **always rendered** (no
    injected closure, unlike `RewardContentSheet`'s) because `ChallengeDetailView` owns its own view
    model, so both presentation sites — the board and the timeline — already have somewhere to send.
    The host's Reports card now names each report's **kind as text** (`reportedContentKind`), since
    a gift is moderated from gift curation but a challenge from challenge authoring, and colour or an
    icon alone would not survive grayscale or VoiceOver (WCAG 1.4.1).
- **Occasion-type starter challenge templates** — an empty-board host can seed editable per-type starter
  challenges (`ChallengeTemplates`). The starter COPY matches the app tone and is fully editable —
  review/replace to taste.

**Landed this session (attended) — the last remaining engineering item:**
- **Transaction test harness — DONE + committed** (branch `feat/transaction-test-harness`, then
  FF-merged to `main`). Proves the balance re-check and idempotency guards against the Firestore
  emulator; non-vacuous; gated so the unit pass skips it; new CI `integration-tests` job. The
  `FirebaseApp.configure()` × test-host concern turned out benign: the host app just needs *a*
  plist (the real one locally, `GoogleService-Info.plist.example` on CI), and the harness uses a
  **secondary** emulator-pointed `FirebaseApp`, leaving the default app alone. See the Known Gaps
  entry above and `integration-tests/README.md`.

**Genuinely NOT done — each needs a human decision or a capability I lack (not avoidance):**
- **EULA / terms** copy (legal); **occasion-template copy** sign-off (product tone); and the standing
  manual prerequisites — app rename + real bundle ID + signing team, Apple Developer account + store
  listing, Sign in with Apple capability, enabling the Anonymous+Apple providers, `tools/export_media.sh`
  before deploy, the live a11y reflow visual check, and **pushing `main` to origin**. *(Superseded
  2026-08-28: the Xcode target-membership item for `PrivacyInfo.xcprivacy` is gone — see the
  Direction entry above; that item never actually needed a human. The Sign in with Apple
  **capability** step below is also now done, via the entitlements file — see above; enabling the
  Anonymous+Apple **providers** in the Firebase console is a separate, still-open step.)*

## Direction (as of 2026-08-22)

### Subsystem #3 slice 3 (media pipeline — audio/voice gifts) is DONE and merged into `main` (as of 2026-08-24)

Landed on `main` by fast-forward (linear history) at `135b23f`; branch `feat/media-gifts-slice-3-audio`
and the SDD workspace (scratchpad, never in the repo) are deleted — git history is the record.
**`main` is still not pushed** (~96 ahead of origin). Like slices 1 and 2, this was **purely
contributor-side authoring** — the celebrant/playback half was already shipped in slice 1
(`RewardContentPresentation.resolve` handles `.audio` → `AudioPlayerView`, `MediaStore.storagePaths`
handles `.audio` → `[contentUrl]`, `AudioPlayerView` plays a local `file://`, `uploadRewardMedia`/
`fileExtension` accept `audio/mpeg`+`audio/mp4`+`audio/x-m4a`, the storage rules' `isPlayableMedia()`
permits `audio/*` <200MB, `GiftCurationView` labels `.audio` "Voice gift"). **No `storage.rules`/
`firestore.rules` change** → the emulator rules suite was correctly not re-run.

Audio was more than a mirror of slice 2 for two reasons: **two input paths** (record + import, not one
picker) and a **new hardware permission + audio-session change**. Delta: a `.voice` case in
`GiftAuthoringViewModel`/`GiftAuthoringView` mirroring `.video` (`selectedAudioURL`, `audioTooLarge`,
`acceptAudio`, `saveAudio`, `audioContentType`, `existingGiftHasAudio`, `.voice` added to every
exhaustive `GiftContentMode` switch and `loadExisting` remapped `.audio` → `.voice`); a new
`AudioRecorderController` (AVAudioRecorder, AAC/.m4a mono, 5-min auto-stop, `AVAudioApplication`
mic-permission, session set to `.playAndRecord`+`.defaultToSpeaker` on start and restored to
`.playback` on **every** exit — stop/cancel/deinit/both catch paths); the record UI (elapsed timer +
motion-gated pulsing dot + Stop, permission-denied row + Settings link); an import path via
`.fileImporter([.mpeg4Audio, .mp3])` (the two formats `fileExtension` maps — no `.bin` fallback,
no WAV import); a **review-before-save** row that replays the picked/recorded clip through the
celebrant-side `AudioPlayerController` before saving; and `INFOPLIST_KEY_NSMicrophoneUsageDescription`
added to BOTH pbxproj config blocks (a plain string, so a build setting works — unlike
`CFBundleURLTypes`; the SOURCE_ROOT `Info.plist` is untouched). Audio uses the SINGLE `contentUrl`
(never `contentUrls`), stores the Storage **path**, badge `waveform`.

**One reusability fix worth knowing:** `AudioPlayerController.loadAudio` was written for a *single*
load; the review player re-loads it on re-record/choose-different, so it now tears down the prior
player + time/status/end observers at the top of `loadAudio` before creating the new ones (AVPlayer
asserts if deallocated with a periodic time observer still attached). This also hardened the shipped
celebrant Retry path. Landed green: Swift `** TEST SUCCEEDED **` (10 new audio VM tests), SwiftLint
`--strict` 0/69. Executed subagent-driven (Sonnet implementers, Opus whole-branch review — 2 Important
findings, both fixed: the loadAudio teardown + an oversized-import temp-file leak). **The recorder is
intentionally hardware-bound and NOT unit-tested** — all authoring logic is tested through the VM's
`acceptAudio` seam (mirroring how video injects `selectedVideoURL`); do not "add coverage" for the
recorder. **Two deferred design Minors:** (1) the now-4-segment gift-type picker
(Letter/Photos/Video/Voice) may truncate on the narrowest device at the largest accessibility text
sizes — folds into the existing "reflow visually unverified" gap; if it truncates switch that picker
to `.menu`; (2) inline text buttons "Stop"/"Open Settings" hit-area width is slightly under the 44pt
iOS recommendation but matches the app's existing inline text buttons. **Still out: only the
media-lifecycle slice** (celebrant purge wiring + expiry reminders + expired state + re-send recovery)
and the two slice-2 deferrals below (in-memory upload; a media thumbnail/preview in the "selected"
row — now also applies to audio). Audio, video, photo, and text gifts are all now authorable.

### Subsystem #3 slice 2 (media pipeline — video gifts) is DONE and merged into `main` (as of 2026-08-24)

Landed on `main` by fast-forward (linear history) at `de5e573`; branch `feat/media-gifts-slice-2-video`
and the SDD workspace are deleted — git history is the record. **`main` is still not pushed** (~90
ahead of origin). This slice was **purely contributor-side authoring** — the celebrant/playback half
was already shipped in slice 1 (`RewardContentPresentation.resolve` handles `.video`,
`MediaStore.storagePaths` handles `.video`, `VideoPlayerView` plays a local `file://` URL,
`uploadRewardMedia`/`fileExtension` accept `video/mp4`+`video/quicktime`, the storage rules permit
`video/*` <200MB, `GiftCurationView` labels+icons `.video`). Delta: a `.video` case in
`GiftAuthoringViewModel`/`GiftAuthoringView` mirroring `.photos`, a `Movie` `Transferable` so the
picked clip's size is checked against the 200MB cap without loading it into memory, `saveVideo`
(writes the Storage **path** to the single `contentUrl`, `contentUrls: nil`, UUID upload folder),
a 200MB-cap UX (`videoTooLarge`), and temp-file cleanup on re-pick/reject/after-save. **No
`storage.rules`/`firestore.rules` change** (so the emulator rules suite was correctly not re-run).
Landed green (Swift `** TEST SUCCEEDED **` 241 test-case passes, SwiftLint `--strict` 0/68), executed
subagent-driven (Sonnet implementer, Opus whole-branch review — essentially clean, 3 temp-file/media
Minors) with two fix waves. **Two deferrals carried to the media-lifecycle slice:** (1) the upload
loads the whole ≤200MB clip into memory via `Data(contentsOf:)` — reusing the shipped
`uploadRewardMedia(data:)` spine; a file-URL/streaming upload is an API change, not a slice-2 change;
(2) a video thumbnail in the "Video selected" confirmation row (photos show thumbnails) — a UX
enhancement (now also applies to audio's "Voice gift ready" row). **Still out: the media-lifecycle
slice (celebrant purge wiring + expiry reminders + expired state + re-send recovery).** Audio gifts
(slice 3, import + record) are now DONE — see the slice 3 block above.

### Subsystem #3 slice 1 (media pipeline — photo gifts) is DONE and merged into `main` (as of 2026-08-24)

Landed on `main` by fast-forward (linear history) at `e0997f1`; branch `feat/media-gifts-slice-1` and
the SDD workspace are deleted — git history is the record. **`main` is still not pushed.** This slice
built the *spine* of the media pipeline on the simplest media (images): `uploadRewardMedia` (returns
the Storage **path**, not a download URL), the `MediaStore` actor (authenticated download → persist to
Documents → local `file://` URL; records `fetchedBy`; `purge` present but unwired — see Known Gaps),
the `RewardContentPresentation` async rework (`.loading` added, media resolves via `MediaStore`, the
dead `.singleImage` case removed), the Letter/Photos authoring selector, the curation content-type
badge + storage-purge-on-delete, and the one `storage.rules` change (reward-media delete widened to
`isCelebrant || isHost`, mutation-tested). **Its reason for existing — closing the reward-media
download-URL leak — is done and verified end-to-end.** Landed green (Swift `** TEST SUCCEEDED **`,
rules 172/172, SwiftLint `--strict` clean), executed subagent-driven with per-task reviews and a
domain-sliced whole-branch review (Swift on Opus, rules on Sonnet, no Criticals) plus one fix wave.
**Still out (from slice 1's vantage): video gifts — done in slice 2 — and audio gifts — done in
slice 3 (see the blocks above) — leaving only the media-lifecycle slice (celebrant purge wiring +
expiry reminders + expired state + re-send recovery).**

### Subsystem #2 slice 1 is DONE and merged into `main` (as of 2026-08-24)

Landed on `main` by fast-forward (linear history) at `f13f7de`, together with subsystem #1's
follow-up cluster; both branches (`feat/content-authoring`, `fix/risk-1-cluster-and-followups`) are
deleted and the SDD workspace is gone — git history is the record now. **`main` is not pushed**
(`origin/main` is ~77 commits behind); publishing stays the deliberate step gated on the three manual
prerequisites in the subsystem-#1 section below. The host authors challenges
(`ChallengeAuthoringView`), each contributor authors one text gift (`GiftAuthoringView`, a fourth
tab), and the host prices, orders, and deletes gifts (`GiftCurationView`) without being able to
rewrite their text. Landed green — Swift `** TEST SUCCEEDED **`, emulator rules suite passing,
SwiftLint `--strict` clean; derive the counts (`grep -c '^\s*it(' firebase-tests/*.test.js`) rather
than trusting a number written here. It was executed subagent-driven with per-task reviews and a
three-domain whole-branch final review (rules/Swift/UI, no Criticals) plus one fix wave. Still out,
deferred to later subsystems: **media gifts** (video/audio/image — subsystem #3, also needs a
`storage.rules` change), **occasion-type templates** (subsystem #4), **participant removal**, and
**occasion settings beyond `isOpen`**.

Rules and invariants this subsystem established (now on `main`):

- **`challenges` and `rewards` are now field-scoped.** `update` splits into a gameplay half (any
  member — unchanged, so the dare and unlock flows keep working), a content half (host or the
  document's own author), and for rewards a curation half (`pointCost`/`sortOrder`, host only).
  `isSecret`, `createdByUserId`, `fromUserId` and `createdAt` are immutable **by omission** from
  every allow-list — `affects()` uses `hasOnly`, so a key in no list cannot be written. Do not add
  a separate immutability clause; it would be dead.
- **A single `updateData` must not mix tiers.** The rules reject a write whose changed keys span
  two allow-lists, and it fails only at runtime, as permission-denied.
- Reward `create` **widened**: a member may now create the gift that is from them. It was host-only.
- `createSecretChallenge`/`updateSecretChallenge` are now `createChallenge`/`updateChallenge`, and
  both partial-update methods take `fields:`.
- `totalChallenges`/`totalRewards` now move with the content, batched inside `FirestoreService`.
  **The decrement is not idempotent** — `deleteDocument` on an absent doc succeeds while
  `increment(-1)` does not, so a re-issued delete would drive the counter negative and
  `checkFinalBadge`'s `totalRewards > 0` then fails forever. This is now defended two ways: a
  `guard !isPerformingAction` on every authoring delete path, and a self-healing `reconcileCounter`
  on the authoring screens that writes the **absolute** observed document count (never a delta) when
  the stored counter disagrees — triggered from the view via `.onChange`, gated on a delivered
  snapshot, idempotent, and it converges. Note the final celebration gates on `totalRewards` only
  (`checkFinalBadge`, `unlockRewardAtomically`); `totalChallenges` drift affects
  `GameState.challengeProgress`, not the badge.

Task 13 reconciled the rest of this file (the Collections table, Known Gaps, README) against slice
1 as shipped.

## Direction — subsystem #1 (as of 2026-08-21)

The app is multi-tenant. Subsystem #1 (event scoping + identity) is **complete — all 16 tasks, plus
the final whole-branch review and its remediation — and merged into `main`** (fast-forward, so
history stays linear and every commit survives). **`main` is not pushed**; `origin/main` is well
behind, and the three manual steps below are why publishing was left as a deliberate decision
rather than a formality.
At the merge point, `main` was green with **166 Swift test cases + 113 emulator rules tests** and
SwiftLint clean across 58 files. Those are `main`'s numbers, not the current branch's — see the
session-5 note below. (Note `xcodebuild`'s "passed on" line count runs higher than the number of
distinct tests — 182 against `main` — because parameterized cases report once per argument; count
unique test names if you need to compare.)

**Follow-up work (the host-panel risk-#1 cluster and ranked follow-ups 2–6 and 8) is now merged into
`main`.** It was on `fix/risk-1-cluster-and-followups` (branched from `main` at `b05a22b`), which
fast-forwarded into `main` on 2026-08-24 together with subsystem #2 and is now deleted. Both tiers and SwiftLint were verified green. Two corrections
to the earlier handoff, both confirmed against the tree rather than assumed: the celebrant
`ShareLink` was **already** fixed by `debeaa7` (`celebrantLink` is nil for a consumed code), and
`main` at `b05a22b` had **1** SwiftLint violation, not 0 — `orphaned_doc_comment` in
`RewardContentSheet.swift`, now fixed.

**Session 5 closed the last two ranked follow-ups.** Use `git rev-list --count main..HEAD` for the
commit total rather than trusting a number written here — the last two attempts to state it were
both stale within the same session, because the documentation commits keep changing their own count.
`ba0cd1a` is the
accessibility pass — Dynamic Type across all 214 font call sites, Reduce Motion gating for all 17
perpetual animations, and AA contrast — `9fb040f` is the CI housekeeping, and `45440ce` is this
guide's own reconciliation. Both tiers were
verified on the tip: **173 Swift test cases** (up from 166) with `** TEST SUCCEEDED **`, and
SwiftLint clean at `--strict` across 58 files. The rules suite was **not** re-run, deliberately: no
rules file was touched, and this project gates that suite on rules changes. So the ranked list from
`progress.md` is now exhausted, and the next work is subsystem #2 host authoring.

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
1. ~~Xcode: add the **Sign in with Apple** capability. The UI now exists and will fail at runtime
   without it.~~ **Done (2026-08-28).** `BirthdayQuest.entitlements` + `CODE_SIGN_ENTITLEMENTS`
   wire it now — see Project Details and the 2026-08-28 Direction entry.
2. Firebase console: enable the **Anonymous** and **Apple** providers. Anonymous gates *everything*
   — without it the app cannot get past launch. Apple gates only the linking path. **Verified
   2026-08-28 against the live project: Anonymous works.** What still fails there is unrelated —
   `fetchMyOccasions` returns permission-denied because the deployed rules predate event-scoping
   (see the 2026-08-28 Direction entry); that's step 3 below plus a rules deploy, not a providers gap.
3. Run `tools/export_media.sh` **before** `firebase deploy` — the new rules deny all access to the
   old `rewards/**` and `proofs/**` prefixes. **As of 2026-08-28 the live project has not had
   `firebase deploy --only firestore:rules,storage` run against it at all**, which is the actual
   current blocker on that project.

Remaining subsystems, unchanged: #2 host authoring (the 39-item gap list), #3 media pipeline
(`MediaStore`, server-as-courier), #4 compliance (moderation, `PrivacyInfo.xcprivacy`, real bundle
ID, rename away from "BirthdayQuest", store listing).

Decisions already made and still binding: no Cloud Functions (rules carry all enforcement); no
lifecycle state machine (`isOpen` is a host toggle, `occasionDate` is for sorting and purge
anchoring only); five occasion types at launch; celebrant must install the app, with **no handover
mode** — which is why the host panel surfaces celebrant-not-joined prominently.
