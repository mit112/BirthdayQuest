# 🎂 BirthdayQuest

A gamified iOS birthday experience where the birthday person completes challenges to earn points and spends them to unlock sentimental rewards — messages, videos, and audio from friends and family. Built as a personal gift for a friend's birthday celebration in NYC.

## The Concept

Five friends share the app. The birthday person ("The Birthday King") earns points by completing fun challenges, then spends those points to unlock heartfelt rewards contributed by friends and family. A living timeline captures the entire journey, growing node by node as challenges are completed and rewards are unlocked. A mysterious final badge awaits at the bottom of the timeline — unlocking only when every reward has been claimed.

The app is the gift. The final badge triggers the handoff of a real, physical surprise.

## Screenshots

*Coming soon — app is pre-release.*

## Tech Stack

- **UI:** SwiftUI (iOS 17+)
- **Architecture:** MVVM
- **Backend:** Firebase (Firestore, Storage, Anonymous Auth)
- **Animations:** ConfettiSwiftUI, SwiftUI native animations
- **Avatars:** DiceBear Lorelei style (local assets with crown overlay for birthday person)
- **Distribution:** TestFlight

## Features

### For the Birthday Person
- **Rewards Carousel** — Infinite-loop horizontal carousel of locked gift cards with frosted glass / glow states
- **Challenge Board** — Scrollable cards with fun illustrations, point values, and difficulty indicators
- **Secret Challenges** — Hidden "???" entry point reveals classified dares from friends
- **Living Timeline** — Vertical animated path that grows with each completed action
- **Final Badge** — Mysterious pulsing badge that unlocks when all rewards are claimed

### For Friends
- **Secret Dare Creation** — Each friend crafts one secret challenge with a spy/dossier aesthetic
- **Shared Timeline** — Watch the birthday person's journey unfold with catch-up animations
- **Profile** — Character identity with quirky fun facts and stats

### Shared
- **Character Select** — Video game lobby-style authentication with swipeable character cards
- **Points System** — Earn from challenges, spend on rewards, animated counters everywhere
- **"Check your timeline →"** — The heartbeat button that appears after every action
- **Skeleton Loading** — Shimmer animations matching each screen's layout
- **Admin Controls** — Hidden panel for the organizer to manage game state

## Project Structure

```
BirthdayQuest/
├── Models/
│   ├── Challenge.swift
│   ├── GameState.swift
│   ├── Reward.swift
│   ├── TimelineEvent.swift
│   └── User.swift
├── Services/
│   ├── DataSeeder.swift
│   ├── FirestoreService.swift
│   └── SessionManager.swift
├── ViewModels/
│   ├── AdminViewModel.swift
│   ├── ChallengeSubmissionViewModel.swift
│   ├── ChallengesViewModel.swift
│   ├── CharacterSelectViewModel.swift
│   ├── RewardsViewModel.swift
│   ├── SecretChallengeViewModel.swift
│   └── TimelineViewModel.swift
├── Views/
│   ├── CharacterSelect/
│   ├── BirthdayBoy/       (Rewards, Challenges, Submissions)
│   ├── Friend/             (Secret Challenge Home)
│   ├── Timeline/           (Timeline, Final Badge)
│   ├── Profile/            (Profile, Admin Controls)
│   └── Components/         (Avatar, Skeleton, Media Players)
├── Extensions/
├── DesignSystem.swift
├── AppConstants.swift
└── Assets.xcassets/        (App Icon, Avatars, Colors)
```

## Firebase Collections

| Collection | Purpose |
|---|---|
| `users` | 5 character profiles with avatars, taglines, roles |
| `challenges` | Regular + secret challenges with point values |
| `rewards` | Sentimental content with point costs |
| `timeline_events` | Grows as actions happen |
| `game_state/main` | Single document tracking points and progress |

## Design Philosophy

**"Headspace meets Duolingo"** — bright, playful, and minimal. Soft purples, warm oranges, gentle pinks. Rounded shapes, generous whitespace, micro-animations on everything. Every screen ships polished — no placeholders.

## Setup

1. Clone the repo
2. Open `BirthdayQuest/BirthdayQuest.xcodeproj` in Xcode
3. Add your own `GoogleService-Info.plist` from Firebase Console
4. Build and run (iOS 17+ device or simulator)

The `DataSeeder` automatically populates Firestore on first launch if collections are empty.

## Key Technical Decisions

- **No voting system** — the birthday person shows proof in person, friends agree, then upload happens and points auto-award
- **Anonymous Auth** — character selection doubles as lightweight authentication
- **Manual Firestore parsing** — `GameState` listener uses dictionary parsing instead of Codable to handle Firestore's Int64/NSNumber type inconsistencies
- **`Timestamp(date: Date())`** — used everywhere instead of `FieldValue.serverTimestamp()` which breaks Codable decoding
- **SessionManager as central hub** — all views read shared state via `@EnvironmentObject`

## Build

```bash
cd BirthdayQuest
xcodebuild -scheme BirthdayQuest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

## License

This is a personal project built as a birthday gift. Not intended for commercial distribution.

---

*Built with ❤️ for a friend's birthday.*
