## Current State (updated Feb 25 — Post skeleton loading states)

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
- Bundle ID: `com.mitsheth.birthdayquest`
- Team ID: `3P89U4WZAB`
- Signing: Automatic
- Deployment target: iOS 26.0

### Seeded Content
- 17 challenges (5 easy @ 25pts, 7 medium @ 50pts, 4 hard @ 75pts, 1 legendary @ 100pts) = 875 total pts
- ✅ All challenges use photo/text/button submission (no video anywhere)
- 7 placeholder rewards (Mit, Kashish, Gaurav, Milloni, Mom, Dad, Family) = 800 total cost
- Reward content is placeholder text — real videos/audio/messages TBD from friends & family
- All content editable in Firestore without code changes.
- DataSeeder checks each collection independently before seeding.

### ⚠️ Content Still Needed
- Profile personalities (taglines, role badges, fun facts) — in progress
- Challenge list — being reviewed and expanded
- Real reward content from friends & family — expected soon

### Architecture Notes
- SessionManager.shared is central state hub — all views read points via @EnvironmentObject
- Do NOT use SessionManager.shared.gameState in computed properties inside ViewModels — SwiftUI won't observe
- NEVER call listenToGameState from ViewModels — it hijacks SessionManager's listener (same "gameState" key) and breaks points updates globally. Use @EnvironmentObject + .onChange in the view instead.
- GameState listener uses manual dictionary parsing, NOT Codable (Firestore Int64/NSNumber issues)
- FieldValue.serverTimestamp() is BANNED — use Timestamp(date: Date()) everywhere
- ConfettiSwiftUI uses `trigger` parameter (not `counter`)
- Firestore settings configured in App init BEFORE any Firestore access (crash fix)
- SubmissionType has safe decoder fallback — unknown values (e.g. old "video" docs) decode as .photo
- Skeleton loading system: `SkeletonView.swift` contains shimmer modifier + screen-specific ghost layouts (RewardsSkeletonView, ChallengesSkeletonView, TimelineSkeletonView, DossierSkeletonView). Each matches the real screen's card dimensions and layout so the transition from loading → content feels seamless.

### Before TestFlight Checklist
- [x] Remove SubmissionType.video from Challenge model + all references
- [x] Update 6 seeded challenges from "video" to "photo" submissionType in Firestore
- [x] Build VideoPlayerView, AudioPlayerView, TextRewardView components
- [x] Update RewardContentSheet to use real components instead of placeholders
- [x] Add AVAudioSession.playback setup in BirthdayQuestApp.swift
- [x] Skeleton loading states on all data screens
- [ ] Populate real profile content (taglines, role badges, fun facts)
- [ ] Finalize challenge list
- [ ] Collect real reward content (videos/audio/text from friends & family)
- [ ] Upload reward content to Firebase Storage `/rewards/{rewardId}/`
- [ ] Update reward docs in Firestore with real contentUrl and contentType
- [ ] Review/edit the 17 challenges in Firestore
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
