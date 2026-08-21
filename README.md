# BirthdayQuest

A gamified iOS app where the person being celebrated completes challenges to earn points and spends them to unlock sentimental rewards — video messages, audio notes, photo galleries, and heartfelt text from friends and family. Built entirely in SwiftUI with a real-time Firebase backend.

## What It Does

One person hosts an occasion — a birthday, anniversary, graduation, farewell, or bachelor/ette — and shares two invite links: one for contributors, one for the person being celebrated. Contributors each write a secret challenge. The celebrant earns points by completing challenges, then spends those points to unlock personalized gifts from the people who matter most.

A living timeline captures every moment — growing node by node with animated bezier paths as challenges are completed and rewards are unlocked. A mysterious final badge pulses at the bottom of the timeline, unlocking only when every reward has been claimed.

Each occasion is its own tenant. Everything lives under `events/{eventId}`, so one install can host or join several celebrations at once and none of them can see each other.

**The app is the gift.**

## Why This Exists

A friend's 30th was coming up and I didn't want to buy a thing. I wanted the people who care about
them to be the gift — but a group chat full of "happy birthday!!" messages is forgettable, and a
shared photo album is something you scroll once.

So I made the birthday person *earn* it. Five of us installed the app for a weekend. They completed
challenges we'd written, and every unlock revealed something one of us had recorded. By Sunday the
timeline had turned into a record of the whole weekend.

It worked. This repo is that app, generalized so it isn't hardcoded to one weekend and one group of
friends, so you can make one for someone you like.

## Screenshots

<p align="center">
  <img src="screenshots/rewards.jpg" width="200" />
  <img src="screenshots/challenges.jpg" width="200" />
  <img src="screenshots/timeline.jpg" width="200" />
</p>
<p align="center">
  <img src="screenshots/secret-dare.jpg" width="200" />
  <img src="screenshots/profile.jpg" width="200" />
</p>

<p align="center">
  <em>Rewards Carousel &nbsp;·&nbsp; Challenge Board &nbsp;·&nbsp; Living Timeline &nbsp;·&nbsp; Secret Dare &nbsp;·&nbsp; Profile</em>
</p>

> These were taken before the multi-occasion rework. The screens are the same; the navigation
> above them now starts from an occasion list rather than a character-select lobby.

## Features

### Rewards Carousel
Infinite-loop horizontal carousel with three card states: **locked** (frosted glass), **affordable** (pulsing gold glow), and **unlocked** (full color with playback). Unlocking triggers an atomic Firestore transaction that verifies the point balance, deducts points, marks the reward, and creates a timeline event — all in a single operation.

### Challenge Board
Challenges carry a point value, one of three difficulty tiers, and one of five categories (physical, social, creative, sentimental, adventure). Any challenge can be **2-in-1** — setting `optionBTitle` makes the detail view present Option A / Option B behind a toggle picker. Submission is universal: every challenge offers Photo, Text, or Done proof options.

A newly created occasion starts with **zero** challenges and **zero** rewards. Host authoring — creating challenges and rewards in-app — is the next subsystem and is not built yet, so for now the only in-app authoring path is a contributor writing their secret challenge. Everything else has to be written straight into Firestore. See [Customization](#customization).

### Secret Challenges
Contributors each create one classified dare through a spy-themed dossier interface with scan-line overlays and monospaced typography. The celebrant discovers these through a hidden "???" entry point that reveals a dark, classified sheet. Secret challenges are created, delivered, and completed through Firestore with real-time sync.

### Living Timeline
Vertical animated path with color-coded nodes: blue gradients for challenges, golden halos for rewards. Each node entrance is staggered with spring animations. The newest node breathes with a pulsing glow. Bezier trail connectors wind organically between nodes in an S-curve pattern with decorative sparkles at midpoints. A bokeh particle field and twinkling sparkle layer create a living background behind the path. The timeline is append-only by security rule — nothing can be edited or deleted after the fact.

### Final Badge
Progressive glow intensifies as more rewards are unlocked. When the last reward is claimed, confetti erupts, haptics fire, and the badge transforms — revealed through a celebration sequence.

### Points Economy
Every challenge sets its own `pointValue` and every reward its own `pointCost`; nothing is derived from content type. Balance a set so the challenges cannot quite cover the rewards and the gap has to be closed by the secret challenges contributors write, and unlocking the final badge requires everyone to participate rather than just the celebrant. All point mutations use `FieldValue.increment` for safe concurrent updates, with transactions protecting balance-dependent operations.

### Additional Features
- **Occasion List** — Active and past occasions, pull to refresh, create or join from the toolbar. Joining works from a pasted invite link or an incoming `birthdayquest://join` URL
- **Host Panel** — Occasion management for the host: invite links, celebrant-joined status, force-completing challenges, force-unlocking rewards, adjusting points, and triggering the final celebration. Shown in the Profile tab only when `isHost` is true
- **Skeleton Loading** — Screen-matched shimmer placeholders on every data view
- **Media Playback** — `VideoPlayerView` and `AudioPlayerView` with buffering states, error recovery, and proper AVPlayer lifecycle management
- **Design System** — Centralized `BQDesign` namespace with color palette, typography scale, spacing tokens, shadow presets, and animation curves

## Architecture

**MVVM + Services** with real-time Firestore synchronization.

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│    Views     │────▶│   ViewModels     │────▶│    Services      │
│  (SwiftUI)   │     │  (@MainActor)    │     │  (Firestore)     │
│              │◀────│  @Published      │◀────│  Listeners       │
└─────────────┘     └──────────────────┘     └─────────────────┘
       │                                              │
       ▼                                              ▼
┌──────────────┐                             ┌─────────────────┐
│  AppSession   │  auth + occasion list      │   Firestore DB   │
│ EventSession  │◀─── Real-time sync ────────│   + Storage      │
│ (@EnvObject)  │  one occasion's scope      │                  │
└──────────────┘                             └─────────────────┘
```

### Key Patterns

- **AppSession** — `@MainActor` `ObservableObject` injected as `@EnvironmentObject` at the root. Owns auth state, the uid, and the user's occasion list, and drives root routing. Knows nothing about any single occasion.
- **EventSession** — One occasion's scope: its `eventId`, the current `Participant`, and the `GameState` listener. Created when an occasion is opened, destroyed on leaving, and it tears down only the listeners it registered. Views read game state and the current participant from here.
- **Event-scoped listener keys** — Listener keys are composed as `name@eventId` in one place (`ListenerKey.scoped`) so registration and removal provably match. Two view models sharing a key would silently kill each other's listener.
- **Two-phase occasion creation** — Firestore evaluates batched writes against *committed* state, so the event document is written alone first; the host participant, initial game state, and membership mirror follow in one batch. The rules gate that batch on `events/{id}.hostUid` rather than on participant membership precisely so it can commit.
- **Atomic Operations** — Reward unlocks use Firestore `Transactions` (read balance → verify → write). Challenge completions use Transactions with idempotency guards (read completion status → bail if already done → write).
- **Manual GameState Parsing** — Dictionary-based parsing with `NSNumber?.intValue` instead of Codable to handle Firestore's Int64/NSNumber type inconsistencies.
- **Timestamps** — `Timestamp(date: Date())` everywhere. `FieldValue.serverTimestamp()` is intentionally avoided because it breaks Codable decoding.

### Project Structure

```
BirthdayQuest/
├── Models/              Occasion, Participant, Challenge, Reward, GameState, TimelineEvent, AvatarCatalog
├── Services/            GameBackend + AuthProviding (protocols), FirestoreService, AuthService,
│                        AppSession, EventSession
├── ViewModels/          9 @MainActor ObservableObject classes, each injected with a GameBackend
├── Views/
│   ├── Occasions/       Occasion list, create, join, per-event container
│   ├── Celebrant/       Rewards carousel, challenge board, submission flow
│   ├── Contributor/     Secret challenge creation (dossier UI)
│   ├── Timeline/        Animated path, bezier connectors, final badge
│   ├── Profile/         Stats, participant roster, host panel
│   └── Components/      Avatar, media players, skeleton loaders, particles
├── Extensions/          Color+Hex, View+Extensions
├── DesignSystem.swift   BQDesign namespace (colors, typography, spacing, shadows, animations)
└── AppConstants.swift   Collection paths, invite-code alphabet, listener keys, Storage paths
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (iOS 26+) |
| Architecture | MVVM |
| Backend | Firebase Firestore (real-time listeners, transactions, batches) |
| Storage | Firebase Storage (media uploads, proof photos) |
| Identity | Firebase Anonymous Auth. The uid is the participant key, so it must survive — an Apple-link path exists in `AuthService`/`AppSession` but has no UI yet. See [SECURITY.md](SECURITY.md) |
| Enforcement | Security rules only. There are no Cloud Functions — `firestore.rules` and `storage.rules` carry the entire trust model |
| Animations | ConfettiSwiftUI, SwiftUI spring/easeInOut, Canvas particles |
| Media | AVKit + AVFoundation (video/audio playback with KVO observation) |
| Logging | OSLog Logger (structured logging with subsystem/category) |
| Avatars | Five bundled CC0 assets, resolved by `avatarId` or by a stable FNV-1a hash of a display name. No network calls |

## Firestore Schema

All occasion content is a subcollection of `events/{eventId}`. Isolation is by **path**, not by query
discipline — a client cannot express a query reaching another occasion, because the path does not
exist for them.

| Path | Key Fields |
|------|-----------|
| `events/{eventId}` | name, occasionType, celebrantName, hostUid, occasionDate, isOpen, createdAt, contributorCode, celebrantCode |
| `events/{id}/participants/{uid}` | name, avatarId, mode (`contributor`\|`celebrant`), isHost, usedCode |
| `events/{id}/challenges/{id}` | title, pointValue, difficulty, category, isSecret, isCompleted, proofUrl, optionBTitle |
| `events/{id}/rewards/{id}` | fromName, pointCost, contentType, contentUrl/contentUrls, isUnlocked, fetchedBy |
| `events/{id}/timeline/{id}` | type, referenceId, subtitle, badgeType, timestamp. Append-only by rule |
| `events/{id}/state/main` | currentPoints, challengesCompleted, rewardsUnlocked, finalBadgeUnlocked |
| `memberships/{uid}/events/{id}` | Thin mirror so a user can list their own occasions: role, isHost, joinedAt |
| `inviteCodes/{CODE}` | Uniqueness reservation and code→event resolution only. `get` is allowed, `list` is denied, so a code you hold resolves but the collection cannot be enumerated |

Invite codes live on the event document, not in a client-readable collection, and joins are
authorized against those fields. The document ID under `participants` is the Firebase uid, which is
what makes impersonation structurally impossible: the rules only permit writing your own document.

Field names are load-bearing. The rules compare against them literally, so renaming one fails at
runtime with permission-denied rather than at compile time.

## Getting Started

### Prerequisites
- **Xcode 26 or newer** (the deployment target is iOS 26.0)
- A Firebase project ([console.firebase.google.com](https://console.firebase.google.com))
- **Cloud Storage for Firebase requires the Blaze (pay-as-you-go) plan** for any project created
  after 2024-10-30. Firestore works on Spark; media uploads do not.

### Setup

```bash
git clone https://github.com/mit112/BirthdayQuest.git
cd BirthdayQuest
open BirthdayQuest/BirthdayQuest.xcodeproj
```

1. **Create a Firebase project** and enable **Cloud Firestore** and **Cloud Storage**.

2. **Enable the auth providers.** Firebase Console → Authentication → Sign-in method → enable
   **Anonymous**. Nothing works without it: the app signs in anonymously on launch and every
   security rule keys off `request.auth.uid`, so with the provider disabled you land on the empty
   state with a connection error. Enable **Apple** too if you intend to work on the account-linking
   path.

3. **Add the Sign in with Apple capability** in Xcode → Signing & Capabilities. Only needed for the
   Apple-link path, which is currently service-layer only, but the link call fails without it.

4. **Deploy the security rules.** This repo ships `firestore.rules` and `storage.rules`:

   ```bash
   npm install -g firebase-tools
   firebase login
   firebase use --add          # select your project
   firebase deploy --only firestore:rules,storage
   ```

   With no Cloud Functions in the project, these rules carry the whole enforcement burden — this
   step is not optional. If you leave Firestore in **production** mode without deploying them,
   every read is denied and the app opens to an empty occasion list.

   > **If your project already has media under the old top-level `rewards/` or `proofs/` paths, run
   > [`tools/export_media.sh`](tools/export_media.sh) BEFORE this deploy.** The current
   > `storage.rules` only grant access under `events/{eventId}/...` and deny everything else, so
   > anything left at the old paths becomes unreachable through the app and recoverable only from
   > the Google Cloud console.
   >
   > ```bash
   > ./tools/export_media.sh <your-storage-bucket> ~/Documents/birthdayquest-archive
   > ```
   >
   > The bucket name is the `STORAGE_BUCKET` value from `GoogleService-Info.plist`. Compare the file
   > count it prints against the Firebase console before deploying.

5. **Add your Firebase config.** Download `GoogleService-Info.plist` from the Firebase Console
   (Project Settings → Your apps → iOS) and save it to `BirthdayQuest/BirthdayQuest/`. See
   [`GoogleService-Info.plist.example`](GoogleService-Info.plist.example) for the expected keys.

   The project uses Xcode folder-synced groups, so dropping the file in that directory is enough —
   no Xcode configuration needed. Because it is not a build input, the app **builds fine without
   it** and then dies at launch on a raw Firebase assertion from the bare `FirebaseApp.configure()`
   call — an unhelpful crash with no message pointing here. If the app crashes immediately on
   launch, this is why.

6. **Set your Team ID** in Xcode → Signing & Capabilities (Xcode prompts automatically). Please
   leave that change out of any commit.

7. **Build and run, then create an occasion.** Tap **Create an occasion**, fill in the occasion
   name, who's being celebrated, the type and date, and your own display name. That writes the
   event, your host participant document, the initial game state, and two invite codes. Share the
   contributor link with friends and the celebrant link with the guest of honour — the host panel
   in the Profile tab has both, and flags it prominently while the celebrant hasn't joined.

> **A new occasion has no challenges and no rewards.** Nothing seeds them, and host authoring isn't
> built yet, so the board and the carousel are empty until you add documents yourself. That's the
> next section.

### Customization

To personalize an occasion:

- **Challenges** — Add documents under `events/{eventId}/challenges` with `title`, `description`,
  `pointValue`, `difficulty`, `category`, `isSecret: false`, `isDelivered: true`,
  `isCompleted: false`, and `createdAt`. Set `optionBTitle` / `optionBDescription` to make it 2-in-1
- **Rewards** — Add documents under `events/{eventId}/rewards` with `fromName`, `title`,
  `pointCost`, `contentType` (`video` / `audio` / `text` / `image`), and `sortOrder`. Upload media to
  Storage under `events/{eventId}/rewards/{rewardId}/{filename}`, then paste the HTTPS download URL
  into `contentUrl`. Image rewards use `contentUrls: [String]` instead; text rewards use
  `contentText`
- **Avatars** — Replace the images in `Assets.xcassets/avatar-0{1..5}.imageset` with your own
  illustrations. `AvatarCatalog.all` is the list of valid ids
- **Occasion types** — `OccasionType` in `Models/Occasion.swift`, including the `celebrantLabel`
  each one shows instead of a gendered default
- **Design** — All visual tokens live in `DesignSystem.swift` under the `BQDesign` namespace

### Build

```bash
xcodebuild -project BirthdayQuest/BirthdayQuest.xcodeproj \
  -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

### Test

Two tiers, and both need to stay green.

```bash
# 1. Swift unit tests (view models, sessions, models, invite codes)
xcodebuild -project BirthdayQuest/BirthdayQuest.xcodeproj \
  -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BirthdayQuestTests \
  test

# 2. Security rules, against the Firebase emulators
cd firebase-tests && npm install && npm test
```

Always scope the first one to `BirthdayQuestTests`. A bare `test` also runs `BirthdayQuestUITests`,
which boots a simulator and launches the app — slow, memory-hungry, and prone to hanging in
teardown. CI passes `-skip-testing:BirthdayQuestUITests` for the same reason. The rules suite needs
Java 17 for the emulators.

Linting runs from the repo root, so it picks up `.swiftlint.yml`:

```bash
swiftlint
```

## Design

The visual language follows a **"Headspace meets Duolingo"** philosophy — warm, playful, and alive.

**Color palette:** Soft purples (`#7C5CFC`), warm pinks (`#FF6B9D`), golden accents (`#F5A623`), cream backgrounds (`#FBF7F4`). Primary actions use a purple-to-pink gradient. Rewards glow gold. Secret challenges use a dark navy palette with red accents.

**Typography:** Rounded design system (SF Rounded) with a clear hierarchy from 34pt hero titles down to 11pt captions. Serif taglines for personality.

**Motion:** Spring animations for entrances, breathing glows for active states, staggered reveals for lists, confetti + haptics for celebrations. Background particle systems (bokeh circles, twinkling sparkles) with deterministic positioning to prevent flicker on re-renders.

## Technical Highlights

A few implementation details worth noting:

- **Path-based tenancy** — Cross-occasion access isn't blocked by a query filter, it's inexpressible: every document lives under `events/{eventId}`, and `GameBackend` has no method that omits the `eventId`
- **Atomic Firestore operations** — Reward unlocks and challenge completions use transactions with idempotency guards, preventing double-tap exploits and partial-failure corruption
- **Real-time sync** — `EventSession` holds one game state listener per open occasion, observed by every view in that occasion through `@EnvironmentObject`, so points and progress stay consistent across tabs
- **Infinite carousel** — 5x loop multiplier with silent boundary-jump logic for seamless infinite scrolling without the memory cost of inflating hundreds of views
- **Canvas-rendered overlays** — Scan-line effects use `Canvas` draw calls instead of hundreds of `Rectangle` views
- **Structured logging** — All services use `OSLog.Logger` with subsystem/category for filterable, level-aware logging
- **Deterministic avatars and animations** — Avatars map a name to a face through an explicit FNV-1a hash rather than `hashValue`, which is per-process seeded and would reshuffle every launch. Background particles derive positions and durations from seed indices, not `random()`, so nothing jumps on tab re-entry

## Known Limitations

Being upfront, because these will bite you if you deploy it:

- **Members are trusted with the score.** The rules gate `state/main` and `rewards.isUnlocked` on
  membership only, so any participant in an occasion can rewrite the point balance or flip a reward
  to unlocked. That's the cost of having no Cloud Functions, and it was a family-sized assumption
  that now applies to anyone holding an invite code. See [SECURITY.md](SECURITY.md).
- **Media URLs are public links.** The Storage rules gate the object *paths* on membership, but the
  app stores Firebase download URLs, which carry their own token and bypass rules entirely. That
  applies to proof photos the app uploads and to any reward media URL you paste in by hand: anyone
  with the URL can view it, forever, with no credential. Don't put anything genuinely private behind
  a reward.
- **No host authoring yet.** A host can manage an occasion but cannot create challenges or rewards
  in the app — those have to be written into Firestore by hand.
- **Sign in with Apple isn't reachable.** Identity is a Firebase anonymous uid. `AuthService` and
  `AppSession` implement linking to an Apple ID in place, preserving the uid, but nothing in the UI
  calls it — so losing the device still means losing every occasion.
- **The atomic transaction logic is untested.** View models are covered through the `GameBackend`
  protocol and a mock backend, and the security rules have their own emulator suite, but
  `unlockRewardAtomically`, `completeChallengeAtomically`, and `adminForceUnlockReward` live inside
  `FirestoreService` — the mock replaces that logic rather than verifying it. Proving the balance
  re-check and idempotency guards needs a Swift↔emulator harness that doesn't exist yet.
- **`birthdayquest://` isn't registered.** Invite links resolve when pasted into the join sheet, but
  the URL scheme is not declared in the target's Info.plist settings, so tapping a link doesn't open
  the app.
- **Near-zero accessibility.** A handful of `accessibilityLabel`s on the occasion screens, and
  nothing else — no VoiceOver labels on the custom controls, no Dynamic Type, no reduce-motion
  handling, against roughly ten `repeatForever` animations. Light mode only.
- **iOS 26.0 minimum.** Set during development to use the newest SwiftUI APIs; it does limit who
  can build it.

## Credits

- Avatar illustrations generated with [DiceBear](https://dicebear.com) — Open Peeps by Pablo Stanley
  and Lorelei by Lisa Wischofsky, both CC0 1.0 (public domain, no attribution required — credited
  anyway). They ship as bundled assets; the app makes no network call for them.
- Confetti by [ConfettiSwiftUI](https://github.com/simibac/ConfettiSwiftUI) (MIT)
- Backend by [Firebase](https://firebase.google.com) (Apache-2.0)

Built with heavy AI assistance (Claude Code) for scaffolding, code review, and documentation. The
architecture, design direction, and every product decision are mine.

## License

MIT License. See [LICENSE](LICENSE) for details.

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

---

Built with SwiftUI + Firebase.
