# BirthdayQuest — Build Plan

## Design Philosophy
"Headspace meets Duolingo" — soft rounded shapes, rich gradients, generous whitespace, micro-animations on everything, layered depth, warm playful colors (soft purples, warm oranges, gentle pinks), illustrations and personality, rounded typography.

Every chunk ships polished. No "we'll polish later."

---

## Chunk 0: Foundation Layer ✅ COMPLETE
Models + Firebase Service + Session Manager + Seed Data + Design System

## Chunk 1: Character Select (Screen 0) ✅ COMPLETE
- Full-screen dark gradient with floating particles
- Horizontal swipe carousel, glow/float animations
- "This is me" claim flow with Firestore lock
- Routes to role-based tab layout

## Chunk 2: Birthday Boy Tab Shell + Rewards Carousel (Screen 1A) ✅ COMPLETE
- 4-tab layout with thematic icons
- Horizontal snap carousel with 3 card states (locked/affordable/unlocked)
- Animated points counter, unlock confirmation, content reveal sheet
- ConfettiSwiftUI on unlock, "Check timeline →" prompt

## Chunk 3: Friends Tab Shell + Secret Challenge Home (Screen 1B) ✅ COMPLETE
- 3-tab layout with spy-red accent
- Dark dossier-themed creation screen with scan-line overlay
- Editable: title, description, submission type, point value
- Save/deliver flow with status tracking

## Chunk 4: Challenge Board (Screen 2) ✅ COMPLETE
- Scrollable challenge cards with category-colored badges
- Difficulty stars, submission type icons
- Secret "???" card with wiggle + shimmer → dark portal sheet
- Secret missions shown per-friend

## Chunk 5: Challenge Submission Flow ✅ COMPLETE
- Detail sheet with hero, info card, type-specific submission
- PhotosPicker for photo/video, text field, button verify
- Firebase Storage upload to /proofs/{challengeId}/
- Atomic: complete → earn points → timeline event → confetti

## Chunk 6: Timeline (Screen 3) ✅ COMPLETE
- Vertical path with connector lines
- Challenge nodes (blue circle + bolt) and Reward nodes (gold star + gift)
- Custom StarShape geometry
- Staggered entrance animation for new events
- Auto-scroll to newest, final badge at bottom
- Final badge: pulsing "?" → golden crown when all rewards unlocked

## Chunk 7: Profile (Screen 4) ✅ COMPLETE
- Avatar hero with glow, name/tagline/role badge
- Stats grid (birthday boy: 4 stats, friend: 2 stats)
- Fun facts cards
- Organizer admin link → AdminControlsView

## Chunk 8: Game State + Polish ✅ COMPLETE
- Shared tab navigation via SessionManager
- "Check timeline →" heartbeat wired end-to-end
- AdminControlsView: points add/remove, day counter, reset
- ScrollViewProxy captured for programmatic scroll

## Chunk 9: Final Polish + TestFlight ⬜ TODO
- App icon design + asset catalog
- Custom launch screen (not just storyboard)
- Haptic audit — verify every interaction has appropriate feedback
- Animation timing pass — ensure nothing feels jarring
- Skeleton/shimmer loading states for slow network
- Error handling audit — graceful failures everywhere
- Firestore security rules (lock down per-role access)
- TestFlight build + distribution
- Seed real challenges and reward content into Firestore
- Source challenge illustration assets (or finalize emoji approach)
- Source/decide avatar library (currently emoji placeholders)
- Test on physical device (mit's iPhone available)

---

## File Structure (37 files)

```
BirthdayQuest/
├── AppConstants.swift
├── BirthdayQuestApp.swift
├── ContentView.swift
├── DesignSystem.swift
├── Extensions/
│   ├── Color+Hex.swift
│   └── View+Extensions.swift
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
│   ├── ChallengeSubmissionViewModel.swift
│   ├── ChallengesViewModel.swift
│   ├── CharacterSelectViewModel.swift
│   ├── RewardsViewModel.swift
│   ├── SecretChallengeViewModel.swift
│   └── TimelineViewModel.swift
└── Views/
    ├── BirthdayBoy/
    │   ├── BirthdayBoyTabView.swift
    │   ├── ChallengeCardView.swift
    │   ├── ChallengeDetailView.swift
    │   ├── ChallengesBoardView.swift
    │   ├── RewardCardView.swift
    │   ├── RewardContentSheet.swift
    │   ├── RewardsCarouselView.swift
    │   ├── SecretChallengesSheet.swift
    │   └── SecretEntryCardView.swift
    ├── CharacterSelect/
    │   ├── CharacterCardView.swift
    │   └── CharacterSelectView.swift
    ├── Components/
    │   ├── FloatingParticlesView.swift
    │   ├── PointsDisplayView.swift
    │   └── StatCard.swift
    ├── Friend/
    │   ├── FriendTabView.swift
    │   └── SecretChallengeHomeView.swift
    ├── Profile/
    │   ├── AdminControlsView.swift
    │   └── ProfileView.swift
    └── Timeline/
        ├── FinalBadgeView.swift
        ├── TimelineNodeView.swift
        └── TimelineView.swift
```

## Critical Path Status
Chunks 0 → 1 → 2 → 4 → 5 → 6 = ALL COMPLETE ✅

## Firestore Status
- Collections: EMPTY (DataSeeder runs on first app launch)
- Seeder creates: 5 users + game_state/main
- Challenges and rewards need to be manually seeded (organizer pre-work)

## Chunk 10: Rewards Playback + Challenge Cleanup (PENDING)
- Remove SubmissionType.video from challenges (all become photo)
- Build VideoPlayerView, AudioPlayerView, TextRewardView
- Update RewardContentSheet with real media players
- Upload real reward content + update Firestore docs
- Full plan: /BirthdayQuest/IMPLEMENTATION_PLAN.md
