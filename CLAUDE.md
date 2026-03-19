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

### Services (singletons)
- **SessionManager** — App state hub (`@EnvironmentObject`), manages navigation, character selection, and real-time GameState sync
- **FirestoreService** — All Firestore CRUD. Uses **transactions** for reward unlocks (balance check required) and **batches** for challenge completions (no balance check). Named listener keys prevent collisions.
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
| `challenges` | 15 regular (seeded) + secret (user-created, `isSecret: true`) |
| `rewards` | 9 rewards with tiered pricing: text/image=50✦, audio=75✦, video=100✦ |
| `timeline_events` | Append-only, created atomically with challenge/reward operations |
| `game_state` | Single doc `main` — all progress tracking |

## Important Conventions

- ViewModels are `@MainActor final class` — do NOT read `SessionManager.shared.gameState` in computed properties (not observable). Views read it from `@EnvironmentObject`.
- Challenge submission uses a universal 3-option picker (Photo / Text / Done) — no per-challenge submission types.
- 2-in-1 challenges have `optionBTitle` / `optionBDescription` optional fields.
- Reward content types: video, audio, text, image. Image rewards use `contentUrls: [String]` array; others use `contentUrl: String`.
- Character claiming uses device-locked `deviceId` in UserDefaults (`bq_selected_character_id`).

## Dependencies (SPM)
- **Firebase SDK** — FirebaseCore, FirebaseFirestore, FirebaseStorage, FirebaseAuth
- **ConfettiSwiftUI** — Celebration animations
- Built-in: AVFoundation, AVKit, Combine

## Project Details
- Bundle ID: `com.example.birthdayquest`
- Firebase Project: `birthdayquest-90578`
- Deployment Target: iOS 26.0
- Source root: `BirthdayQuest/BirthdayQuest/` (nested due to Xcode project structure)
