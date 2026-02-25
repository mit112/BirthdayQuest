## Current State (updated Feb 25 — Post Chunk 9, Pre-Content)

### What's Done
- **ALL 9 CHUNKS COMPLETE.** 39+ Swift files, zero compiler errors.
- Every screen built and functional: Character Select, Rewards Carousel, Challenges Board, Challenge Submission, Secret Challenge Home, Timeline, Profile, Admin Controls.
- Points system fully working end-to-end.
- "Check timeline →" heartbeat wired across all flows.
- DiceBear Micah avatars with crown overlay for birthday boy.
- App icon: warm gradient crown (light + dark variants) in asset catalog.
- Launch screen: warm cream background (LaunchBackground color set, wired in pbxproj).
- Timeline polish: 96px final badge, improved trail opacity, visible empty state dots.
- Testing shortcuts reverted (0 TODOs remaining).
- Bundle ID: `com.mitsheth.birthdayquest`
- Team ID: `3P89U4WZAB`
- Signing: Automatic

### Seeded Content
- 17 challenges (5 easy @ 25pts, 7 medium @ 50pts, 4 hard @ 75pts, 1 legendary @ 100pts) = 875 total pts
- ⚠️ 6 challenges still have `submissionType: "video"` — need changing to `"photo"` (code + Firestore)
- 7 placeholder rewards (Mit, Kashish, Gaurav, Milloni, Mom, Dad, Family) = 800 total cost
- Reward content is placeholder text — real videos/audio/messages TBD from friends & family
- RewardContentSheet has placeholders for video/audio — real players not yet built
- All content editable in Firestore without code changes.
- DataSeeder checks each collection independently before seeding.

### ⚠️ CRITICAL: Deployment Target
- Currently set to iOS 26.0 in BOTH project-level build configs (Debug + Release)
- Must lower to 17.0 in Xcode if friends aren't on iOS 26
- Lowering may surface compile errors if any iOS 26-only APIs were used — needs testing

### Architecture Notes
- SessionManager.shared is central state hub — all views read points via @EnvironmentObject
- Do NOT use SessionManager.shared.gameState in computed properties inside ViewModels — SwiftUI won't observe
- NEVER call listenToGameState from ViewModels — it hijacks SessionManager's listener (same "gameState" key) and breaks points updates globally. Use @EnvironmentObject + .onChange in the view instead.
- GameState listener uses manual dictionary parsing, NOT Codable (Firestore Int64/NSNumber issues)
- FieldValue.serverTimestamp() is BANNED — use Timestamp(date: Date()) everywhere
- ConfettiSwiftUI uses `trigger` parameter (not `counter`)
- Firestore settings configured in App init BEFORE any Firestore access (crash fix)

### Next Implementation (IMPLEMENTATION_PLAN.md)
- **Part 1:** Remove video submission from challenges (SubmissionType.video → all become .photo)
- **Part 2:** Build real reward content playback:
  - VideoPlayerView (AVPlayer from AVKit, auto-play, loading states)
  - AudioPlayerView (custom UI, waveform progress, AVPlayer for remote URLs)
  - TextRewardView (warm card, decorative quotes, scrollable)
- Store HTTPS download URLs directly in Firestore `contentUrl` (not gs:// paths)
- ~2 hours coding, zero risk to existing screens

### Before TestFlight Checklist
- [ ] Remove SubmissionType.video from Challenge model + all references
- [ ] Update 6 seeded challenges from "video" to "photo" submissionType
- [ ] Build VideoPlayerView, AudioPlayerView, TextRewardView components
- [ ] Update RewardContentSheet to use real components instead of placeholders
- [ ] Add AVAudioSession.playback setup in BirthdayQuestApp.swift
- [ ] Lower deployment target to iOS 17.0 (if needed)
- [ ] Fix any compile errors from deployment target change
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
- Services: `Services/` (FirestoreService.swift, SessionManager.swift, DataSeeder.swift, StorageService.swift)
- ViewModels: `ViewModels/` (one per major screen)
- Views: `Views/` (CharacterSelect/, BirthdayBoy/, Friend/, Timeline/, Profile/, Components/)
- Design System: `Design/BQDesign.swift`
- Assets: `Assets.xcassets/` (AppIcon, LaunchBackground, AccentColor)

### Build Command
```
cd /Users/mitsheth/Documents/BirthdayQuest/BirthdayQuest
xcodebuild -scheme BirthdayQuest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Physical Device
- "mit's iPhone" (arm64, id: 00008120-000875393644A01E)
