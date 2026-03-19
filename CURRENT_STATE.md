## Current State (updated Feb 28 — Live & in use)

### What's Done
- **ALL CHUNKS COMPLETE.** 47 Swift files, zero compiler errors.
- Every screen built and functional: Character Select, Rewards Carousel, Challenges Board, Challenge Submission, Secret Challenge Home, Timeline, Profile, Admin Controls.
- Points system fully working end-to-end.
- "Check timeline →" heartbeat wired across all flows.
- Skeleton loading states on all data screens (shimmer animation, screen-matched ghost layouts).
- DiceBear Lorelei avatars — local assets per character, crown overlay for birthday boy.
- App icon: warm gradient crown (light + dark variants) in asset catalog.
- Launch screen: warm cream background (LaunchBackground color set, wired in pbxproj).
- Timeline polish: 96px final badge, improved trail opacity, visible empty state dots.
- Timeline nodes are tappable → opens challenge detail or reward content sheet.
- Testing shortcuts reverted (0 TODOs remaining).
- Video submission fully removed from challenges (code + Firestore).
- Reward content players built: VideoPlayerView, AudioPlayerView (with scrubbing/skip), TextRewardView, **ImageGalleryView** (swipeable multi-image gallery with page dots).
- RewardContentSheet wired to real media players + gallery support via `contentUrls` array.
- AVAudioSession.playback configured in app init.
- Infinite looping rewards carousel with centered cards.
- PIN override system: universal PIN `1234` for claimed characters.
- **Challenge system:** Universal 3-option submission (photo/text/completed). 4 challenges are 2-in-1 with optionBTitle/optionBDescription.
- **Profile personalization:** All 5 characters have custom taglines, fun facts, and per-character emojis.
- Bundle ID: `com.example.birthdayquest`
- Team ID: `XXXXXXXXXX`
- Signing: Automatic
- Deployment target: iOS 26.0

### Live Firestore Content (Feb 28)

#### Challenges (15 regular + 4 secret slots)
- 3 easy @ 35 pts, 7 medium @ 50-60 pts, 2 hard @ 75 pts, 1 legendary @ 100 pts
- + "Birthday Pushups" (25 pts, easy), "Arm Wrestling Champion" (50 pts, medium), "Digital Detox Weekend" (50 pts, medium)
- 4 of these are 2-in-1 challenges
- Total regular challenge points: ~790 pts
- + up to 4 secret challenges from friends (~200-300 pts)
- **Grand total earnable: ~990-1090 pts**

#### Rewards (9 total, 800 pts total cost)
| # | From | Type | Cost | Status |
|---|------|------|------|--------|
| 1 | Sam | Audio | 50 | ✅ Real audio uploaded |
| 2 | Jordan | Video | 100 | ✅ Real video uploaded |
| 3 | Riley | Video | 100 | ❌ Placeholder — needs real video |
| 4 | Morgan | Video | 100 | ❌ Placeholder — needs real video |
| 5 | Family | Video | 100 | ✅ Real video uploaded |
| 6 | Chris | Video | 100 | ✅ Real video uploaded |
| 7 | Taylor | Video | 100 | ✅ Real video uploaded |
| 8 | Jamie | Video | 100 | ✅ Real video uploaded |
| 9 | Group Photos | Image gallery | 50 | ✅ 10 photos uploaded (swipeable) |

**Pricing tiers:** Audio = 50, Video = 100, Image gallery = 50
**Points economy:** 800 cost vs ~1000+ earnable = ~200-290 surplus (healthy)

### ⚠️ Content Still Needed
- **Riley's video** — currently has placeholder URL
- **Morgan's video** — currently has empty URL

### Architecture Notes
- SessionManager.shared is central state hub — all views read points via @EnvironmentObject
- Do NOT use SessionManager.shared.gameState in computed properties inside ViewModels — SwiftUI won't observe
- NEVER call listenToGameState from ViewModels — it hijacks SessionManager's listener (same "gameState" key)
- GameState listener uses manual dictionary parsing, NOT Codable (Firestore Int64/NSNumber issues)
- FieldValue.serverTimestamp() is BANNED — use Timestamp(date: Date()) everywhere
- ConfettiSwiftUI uses `trigger` parameter (not `counter`)
- `submissionType` field removed from Challenge model — universal 3-option picker in UI
- 2-in-1 challenges: `optionBTitle` and `optionBDescription` are optional fields
- Reward model supports both `contentUrl` (single) and `contentUrls` (array) for multi-image gallery
- ImageGalleryView: TabView-based swipeable gallery with custom page dots, used when contentUrls has >1 entry

### Key File Paths
- Project root: `BirthdayQuest/`
- Source code: `BirthdayQuest/BirthdayQuest/`
- Models: `Models/` (User.swift, Reward.swift, Challenge.swift, TimelineEvent.swift, GameState.swift)
- Services: `Services/` (FirestoreService.swift, SessionManager.swift, DataSeeder.swift)
- ViewModels: `ViewModels/` (one per major screen)
- Views: `Views/` (CharacterSelect/, BirthdayBoy/, Friend/, Timeline/, Profile/, Components/)
- Components: `Views/Components/` (AudioPlayerView, AvatarView, FloatingParticlesView, ImageGalleryView, PointsDisplayView, SkeletonView, StatCard, TextRewardView, TimelineBackgroundView, VideoPlayerView)
- Design System: `DesignSystem.swift` (BQDesign namespace)

### Build Command
```
cd BirthdayQuest
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Physical Device
- Developer iPhone (arm64)
