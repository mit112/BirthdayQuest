# BirthdayQuest

A gamified iOS birthday app where the birthday person completes challenges to earn points and spends them to unlock sentimental rewards — video messages, audio notes, photo galleries, and heartfelt text from friends and family. Built entirely in SwiftUI with a real-time Firebase backend.

## What It Does

Five people share the app. One is the birthday person. The other four are friends who each contribute a secret challenge and a reward. The birthday person earns points by completing fun, social, and creative challenges throughout their birthday weekend, then spends those points to unlock personalized gifts from the people who matter most.

A living timeline captures every moment — growing node by node with animated bezier paths as challenges are completed and rewards are unlocked. A mysterious final badge pulses at the bottom of the timeline, unlocking only when every reward has been claimed.

**The app is the gift.**

## Features

### Rewards Carousel
Infinite-loop horizontal carousel with three card states: **locked** (frosted glass), **affordable** (pulsing gold glow), and **unlocked** (full color with playback). Unlocking triggers an atomic Firestore transaction that verifies the point balance, deducts points, marks the reward, and creates a timeline event — all in a single operation.

### Challenge Board
15 regular challenges across five categories (physical, social, creative, sentimental, adventure) with three difficulty tiers. Four challenges are **2-in-1** — presenting Option A / Option B via a toggle picker in the detail view. Submission is universal: every challenge offers Photo, Text, or Done proof options.

### Secret Challenges
Friends each create one classified dare through a spy-themed dossier interface with scan-line overlays and monospaced typography. The birthday person discovers these through a hidden "???" entry point that reveals a dark, classified sheet. Secret challenges are created, delivered, and completed through Firestore with real-time sync.

### Living Timeline
Vertical animated path with color-coded nodes: blue gradients for challenges, golden halos for rewards. Each node entrance is staggered with spring animations. The newest node breathes with a pulsing glow. Bezier trail connectors wind organically between nodes in an S-curve pattern with decorative sparkles at midpoints. A bokeh particle field and twinkling sparkle layer create a living background behind the path.

### Final Badge
Progressive glow intensifies as more rewards are unlocked. When the last reward is claimed, confetti erupts, haptics fire, and the badge transforms — revealed through a celebration sequence.

### Points Economy
Tiered reward pricing (text/image = 50, audio = 75, video = 100) balanced against challenge point values (35–100) to ensure completing ~60–70% of challenges unlocks everything. All point mutations use `FieldValue.increment` for safe concurrent updates, with transactions protecting balance-dependent operations.

### Additional Features
- **Character Select** — Video game lobby aesthetic with swipeable cards and device-locked claiming
- **Admin Controls** — Hidden organizer panel for managing game state, force-completing challenges, and triggering the final celebration
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
┌─────────────┐                              ┌─────────────────┐
│ SessionMgr  │◀─────── Real-time sync ──────│   Firestore DB   │
│ (@EnvObject) │                              │   + Storage      │
└─────────────┘                              └─────────────────┘
```

### Key Patterns

- **SessionManager** — `@MainActor` singleton injected as `@EnvironmentObject`. Central hub for app state, navigation, and real-time game state sync. Views read points and progress from here, never from ViewModel computed properties (not observable).
- **FirestoreService** — Singleton with named listener keys to prevent collisions when multiple views subscribe to the same collection. Listener cleanup on view disappear.
- **Atomic Operations** — Reward unlocks use Firestore `Transactions` (read balance → verify → write). Challenge completions use Transactions with idempotency guards (read completion status → bail if already done → write).
- **Manual GameState Parsing** — Dictionary-based parsing with `NSNumber?.intValue` instead of Codable to handle Firestore's Int64/NSNumber type inconsistencies.
- **Timestamps** — `Timestamp(date: Date())` everywhere. `FieldValue.serverTimestamp()` is intentionally avoided because it breaks Codable decoding.

### Project Structure

```
BirthdayQuest/
├── Models/              5 Codable structs (User, Challenge, Reward, GameState, TimelineEvent)
├── Services/            FirestoreService, SessionManager, DataSeeder
├── ViewModels/          7 @MainActor ObservableObject classes
├── Views/
│   ├── CharacterSelect/ Swipeable character cards with claim flow
│   ├── BirthdayBoy/     Rewards carousel, challenge board, submission flow
│   ├── Friend/          Secret challenge creation (dossier UI)
│   ├── Timeline/        Animated path, bezier connectors, final badge
│   ├── Profile/         Stats, fun facts, admin controls
│   └── Components/      Avatar, media players, skeleton loaders, particles
├── Extensions/          Color+Hex, View+Extensions
├── DesignSystem.swift   BQDesign namespace (colors, typography, spacing, shadows, animations)
└── AppConstants.swift   Character IDs, Firestore collection names
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (iOS 17+) |
| Architecture | MVVM |
| Backend | Firebase Firestore (real-time listeners, transactions, batches) |
| Storage | Firebase Storage (media uploads, proof photos) |
| Auth | Firebase Anonymous Auth (character-as-identity) |
| Animations | ConfettiSwiftUI, SwiftUI spring/easeInOut, Canvas particles |
| Media | AVKit + AVFoundation (video/audio playback with KVO observation) |
| Logging | OSLog Logger (structured logging with subsystem/category) |
| Avatars | DiceBear Open Peeps (local assets with per-character customization) |

## Firestore Schema

| Collection | Documents | Key Fields |
|------------|-----------|------------|
| `users` | 5 character profiles | name, role, avatarId, tagline, funFacts, claimed, deviceId |
| `challenges` | 15 regular + user-created secrets | title, pointValue, difficulty, category, isSecret, isCompleted, proofUrl |
| `rewards` | 9 tiered rewards | fromName, pointCost, contentType, contentUrl/contentUrls, isUnlocked |
| `timeline_events` | Append-only | type, referenceId, title, subtitle, badgeType, timestamp |
| `game_state/main` | 1 singleton | currentPoints, challengesCompleted, rewardsUnlocked, finalBadgeUnlocked |

## Getting Started

### Prerequisites
- Xcode 16+ with iOS 17+ SDK
- A Firebase project ([console.firebase.google.com](https://console.firebase.google.com))

### Setup

```bash
git clone https://github.com/YOUR_USERNAME/BirthdayQuest.git
cd BirthdayQuest
open BirthdayQuest/BirthdayQuest.xcodeproj
```

1. **Create a Firebase project** and enable:
   - Cloud Firestore
   - Firebase Storage
   - Anonymous Authentication
2. **Download `GoogleService-Info.plist`** from Firebase Console and place it in `BirthdayQuest/BirthdayQuest/`
3. **Set your Team ID** in Xcode → Signing & Capabilities (Xcode will prompt automatically)
4. **Build and run** on a simulator or device

The `DataSeeder` automatically populates Firestore with sample characters, challenges, and rewards on first launch — no manual database setup needed.

### Customization

To personalize for your own birthday celebration:

- **Characters** — Edit `DataSeeder.seedUsers()` with your own names, taglines, and fun facts
- **Challenges** — Edit `DataSeeder.seedChallenges()` to add your own challenges
- **Rewards** — Upload media to Firebase Storage and update `DataSeeder.seedRewards()` with download URLs
- **Avatars** — Replace images in `Assets.xcassets/avatar-*.imageset` with your own illustrations
- **Design** — All visual tokens live in `DesignSystem.swift` under the `BQDesign` namespace

### Build

```bash
xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

## Design

The visual language follows a **"Headspace meets Duolingo"** philosophy — warm, playful, and alive.

**Color palette:** Soft purples (`#7C5CFC`), warm pinks (`#FF6B9D`), golden accents (`#F5A623`), cream backgrounds (`#FBF7F4`). Primary actions use a purple-to-pink gradient. Rewards glow gold. Secret challenges use a dark navy palette with red accents.

**Typography:** Rounded design system (SF Rounded) with a clear hierarchy from 34pt hero titles down to 11pt captions. Serif taglines for personality.

**Motion:** Spring animations for entrances, breathing glows for active states, staggered reveals for lists, confetti + haptics for celebrations. Background particle systems (bokeh circles, twinkling sparkles) with deterministic positioning to prevent flicker on re-renders.

## Technical Highlights

A few implementation details worth noting:

- **Atomic Firestore operations** — Reward unlocks and challenge completions use transactions with idempotency guards, preventing double-tap exploits and partial-failure corruption
- **Real-time sync** — `SessionManager` maintains a single game state listener that all views observe through `@EnvironmentObject`, ensuring points and progress are always consistent across tabs
- **Infinite carousel** — 5x loop multiplier with silent boundary-jump logic for seamless infinite scrolling without the memory cost of inflating hundreds of views
- **Canvas-rendered overlays** — Scan-line effects use `Canvas` draw calls instead of hundreds of `Rectangle` views
- **Structured logging** — All services use `OSLog.Logger` with subsystem/category for filterable, level-aware logging
- **Deterministic animations** — Background particles derive positions and durations from seed indices, not `random()`, preventing visual jumps on tab re-entry

## License

MIT License. See [LICENSE](LICENSE) for details.

---

Built with SwiftUI + Firebase.
