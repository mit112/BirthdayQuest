## Current State (updated Feb 26 — Post challenge system overhaul)

### What's Done
- **ALL 9 CHUNKS + CHUNK 10 COMPLETE.** 46+ Swift files, zero compiler errors.
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
- Reward content players built: VideoPlayerView, AudioPlayerView (with scrubbing/skip), TextRewardView.
- RewardContentSheet wired to real media players.
- AVAudioSession.playback configured in app init.
- Infinite looping rewards carousel with centered cards.
- Points stat icon color fixed (was invisible white on white).
- Points update bug fixed (no duplicate gameState listeners).
- Timeline scroll on reward unlock fixed (matching challenge behavior).
- PIN override system: universal PIN `0228` for claimed characters.
- **Challenge system overhaul (Feb 26):**
  - Removed hardcoded `submissionType` from Challenge model entirely.
  - Every challenge now shows **universal 3-option submission** (photo / text / completed) via a tab picker in ChallengeDetailView.
  - Added **2-in-1 challenge support**: `optionBTitle` + `optionBDescription` fields on Challenge model. Detail view shows Option A / Option B toggle that swaps title + description. 4 challenges use this.
  - Removed submission type picker from Secret Challenge creation (friends no longer choose a type).
  - Challenge card metadata row shows orange ⚡ "2-in-1" badge for dual-option challenges.
  - Seed data replaced with final 12-challenge list from CHALLENGES.md (3 easy, 6 medium, 2 hard, 1 legendary = 12 total, 635 total pts).
  - Fixed Kashish's pronoun in reward teaser ("He" not "She").
- **Profile personalization (Feb 26):**
  - All 5 character profiles updated with personalized taglines, fun facts, and per-character emojis.
  - Aaryan: "Main character energy. Side character track record." (📉🤖⚽)
  - Mit: "Will call you at 3am. Will also build you an app." (🍥🤷☕)
  - Kashish: "Runs on chai, copium, and vape clouds." (🏴‍☠️🛒⚽)
  - Gaurav: "Dodges group trips like it's cardio." (📱💃🎃)
  - Milloni: "Her gifts have lore AND perfect wrapping?!" (🥂🌧️👩‍🍳)
  - ProfileView emoji system changed from hardcoded array to per-character emoji map.
  - Firestore `users` collection updated directly (no wipe needed).
  - DataSeeder updated to match so fresh installs get correct data.
- Bundle ID: `com.mitsheth.birthdayquest`
- Team ID: `3P89U4WZAB`
- Signing: Automatic
- Deployment target: iOS 26.0

### Seeded Content
- 12 challenges (3 easy @ 35pts, 6 medium @ 50-60pts, 2 hard @ 75pts, 1 legendary @ 100pts) = 635 total pts from regular challenges
- 4 of 12 are 2-in-1 challenges (Blind Menu Roulette, Stranger Photo, Karaoke Roulette, Letter/Time Capsule)
- + up to 4 secret challenges from friends (25-100 pts each) = ~100-400 pts additional
- Grand total available: ~735-1035 pts
- ✅ All challenges use universal submission (photo/text/completed — no hardcoded type)
- 7 rewards with tiered pricing by content type:
  - **Tier 1 (Text): 50 ✦** — Mit, Milloni, Mom (3 × 50 = 150)
  - **Tier 2 (Audio): 75 ✦** — Kashish, Dad (2 × 75 = 150)
  - **Tier 3 (Video): 100 ✦** — Gaurav, Family (2 × 100 = 200)
  - **Current total cost: 500 ✦** (targeting 9 rewards total, ~650 ✦ when complete)
  - Pricing auto-derived from `RewardContentType.defaultPointCost` — set content type and cost follows
- DataSeeder expanded to 9 placeholder rewards (2 new: "The Squad" video, "???" audio mystery)
- Reward content is placeholder text — real videos/audio/messages TBD from friends & family
- All content editable in Firestore without code changes.
- DataSeeder checks each collection independently before seeding.

### ⚠️ Content Still Needed
- Real reward content from friends & family — expected soon
- Challenge list personalization (inside jokes, specific photos to recreate, etc.)
- ⚠️ **Must wipe existing Firestore challenges** for new seed data to take effect (DataSeeder skips if non-secret challenges already exist)

### Architecture Notes
- SessionManager.shared is central state hub — all views read points via @EnvironmentObject
- Do NOT use SessionManager.shared.gameState in computed properties inside ViewModels — SwiftUI won't observe
- NEVER call listenToGameState from ViewModels — it hijacks SessionManager's listener (same "gameState" key) and breaks points updates globally. Use @EnvironmentObject + .onChange in the view instead.
- GameState listener uses manual dictionary parsing, NOT Codable (Firestore Int64/NSNumber issues)
- FieldValue.serverTimestamp() is BANNED — use Timestamp(date: Date()) everywhere
- ConfettiSwiftUI uses `trigger` parameter (not `counter`)
- Firestore settings configured in App init BEFORE any Firestore access (crash fix)
- `submissionType` field is **gone** from Challenge model. Old Firestore docs with this field are silently ignored (not in CodingKeys). The `SubmissionType` enum still exists — used by `ChallengeSubmissionViewModel.selectedSubmissionType` for the UI picker.
- 2-in-1 challenges: `optionBTitle` and `optionBDescription` are optional fields. Custom `init(from decoder:)` defaults them to nil so existing Firestore docs without these fields decode fine.
- Skeleton loading system: `SkeletonView.swift` contains shimmer modifier + screen-specific ghost layouts (RewardsSkeletonView, ChallengesSkeletonView, TimelineSkeletonView, DossierSkeletonView). Each matches the real screen's card dimensions and layout so the transition from loading → content feels seamless.

### Before TestFlight Checklist
- [x] Remove SubmissionType.video from Challenge model + all references
- [x] Build VideoPlayerView, AudioPlayerView, TextRewardView components
- [x] Update RewardContentSheet to use real components instead of placeholders
- [x] Add AVAudioSession.playback setup in BirthdayQuestApp.swift
- [x] Skeleton loading states on all data screens
- [x] Remove hardcoded submissionType — universal 3-option submission
- [x] Build 2-in-1 card UI for dual-option challenges
- [x] Replace seed data with final 12-challenge list from CHALLENGES.md
- [ ] **Wipe Firestore challenges collection** so new seed data takes effect
- [ ] Collect real reward content (videos/audio/text from friends & family)
- [ ] Upload reward content to Firebase Storage `/rewards/{rewardId}/`
- [ ] Update reward docs in Firestore with real contentUrl and contentType
- [x] **Personalize all 5 character profiles** (taglines, fun facts, per-character emojis)
- [ ] Personalize challenge descriptions with inside jokes
- [ ] Test video/audio playback on real device (Simulator has AVPlayer quirks)
- [ ] Archive → Distribute → TestFlight Internal Testing
- [ ] Add 4 friends as internal testers in App Store Connect
- [ ] Share TestFlight link

### TestFlight Steps
1. Xcode → set destination to "Any iOS Device (arm64)"
2. Product → Archive
3. Organizer → Distribute App → TestFlight & App Store
4. App Store Connect → TestFlight → add internal testers
5. Share link via iMessage

### Key File Paths
- Project root: `/Users/mitsheth/Documents/BirthdayQuest/BirthdayQuest/`
- Source code: `/Users/mitsheth/Documents/BirthdayQuest/BirthdayQuest/BirthdayQuest/`
- Models: `Models/` (User.swift, Reward.swift, Challenge.swift, TimelineEvent.swift, GameState.swift)
- Services: `Services/` (FirestoreService.swift, SessionManager.swift, DataSeeder.swift)
- ViewModels: `ViewModels/` (one per major screen)
- Views: `Views/` (CharacterSelect/, BirthdayBoy/, Friend/, Timeline/, Profile/, Components/)
- Design System: `DesignSystem.swift` (BQDesign namespace)
- Assets: `Assets.xcassets/` (AppIcon, LaunchBackground, AccentColor)

### Build Command
```
cd /Users/mitsheth/Documents/BirthdayQuest/BirthdayQuest
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Physical Device
- "mit's iPhone" (arm64, id: 00008120-000875393644A01E)
