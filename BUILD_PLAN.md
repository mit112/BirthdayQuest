# BirthdayQuest — Build Plan

## Design Philosophy
"Headspace meets Duolingo" — soft rounded shapes, rich gradients, generous whitespace, micro-animations on everything, layered depth, warm playful colors (soft purples, warm oranges, gentle pinks), illustrations and personality, rounded typography.

Every chunk ships polished. No "we'll polish later."

---

## Chunk 0: Foundation Layer
Models + Firebase Service + Session Manager + Seed Data

- 5 Firestore models matching blueprint: `User`, `Reward`, `Challenge`, `TimelineEvent`, `GameState`
- FirestoreService — all CRUD + real-time listeners
- SessionManager — persists selected character, exposes role checks
- AppConstants — character IDs, collection names
- Seed Firestore: 5 users (Alex, Sam, Jordan, Riley, Morgan)
- Collections: `users`, `rewards`, `challenges`, `timeline_events`, `game_state/main`
- Roles: `birthday_boy`, `friend`, `organizer`
- NO voting. Challenges: `isCompleted`, `proofUrl`, `proofType`

## Chunk 1: Character Select (Screen 0)
- Full-screen immersive gradient background
- Horizontal swipe carousel of 5 characters on a "platform"
- Alex: golden crown glow. Friends: Secret Agent vibe
- "This is me" button — scale + haptic + transition
- Claiming: `claimed: true` in Firestore, greyed for others
- Routes to correct tab layout by role

## Chunk 2: Birthday Boy Tab Shell + Rewards Carousel (Screen 1A)
- 4 tabs: Rewards → Challenges → Timeline → Profile
- Thematic tab icons (gift, sword, compass, avatar)
- Infinite horizontal carousel with tall reward cards
- Card states: Locked (frosted glass), Affordable (pulse glow), Unlocked (full color)
- Points balance animated counter with ✦
- Unlock flow: confirm → deduct → flip animation → content → "Check timeline →"

## Chunk 3: Friends Tab Shell + Secret Challenge Home (Screen 1B)
- 3 tabs: Secret Challenge → Timeline → Profile
- Spy/classified themed creation screen
- Editable: title, description, submission type, point value
- Status: Not delivered / Delivered / Completed
- Dark dossier aesthetic, stamp effects, scan-line overlay

## Chunk 4: Challenge Board (Screen 2)
- Points balance at top
- Vertical scrollable challenge cards
- Each: illustration left, title + desc + points + difficulty + submission icon right
- Clean white cards, soft shadows, rounded corners
- Completed: checkmark overlay, muted
- Secret "???" card at bottom — wiggles/glimmers → portal → dark sub-screen

## Chunk 5: Challenge Submission Flow
- Detail sheet on tap
- Submission UI by type: photo/video/text/button
- Upload to Firebase Storage `/proofs/{challengeId}/`
- Auto-award points, update game_state, add timeline_event
- Confetti + haptic + animated counter + "Check timeline →"

## Chunk 6: Timeline (Screen 3)
- Vertical path with decorative trail
- Empty at start: final badge + "Your journey begins..."
- Challenge nodes: circular, blue tint, illustration
- Reward nodes: star/gift, golden tint, tappable
- Decorative dots/sparkles along trail
- Final Badge: pulsing "?", unlocks when ALL rewards done → massive celebration
- Sequential "catching up" animation for friends

## Chunk 7: Profile (Screen 4)
- Large avatar with role-specific background
- Name, tagline, role badge
- Birthday Boy stats: points, challenges, rewards, secrets
- Friend stats: challenge status, "Watching since Day 1"
- Personality cards: quirky fun facts

## Chunk 8: Game State + Polish
- game_state/main listener for global sync
- Points sync across screens real-time
- "Check timeline →" button: switches tab, scrolls, animates
- Organizer admin controls (hidden, for organizer)
- Edge cases

## Chunk 9: Final Polish + TestFlight
- App icon, launch screen
- Haptic audit, animation timing pass
- Skeleton loading states
- Error handling, Firestore security rules
- TestFlight build

---

## Critical Path (if racing deadline)
Chunks 0 → 1 → 2 → 4 → 5 → 6

## Current State
- Firestore: EMPTY (wiped clean)
- Codebase: BirthdayQuestApp.swift (Firebase init), ContentView.swift (placeholder), Color+Hex.swift, empty MVVM folders
- Firebase SDK, ConfettiSwiftUI, Lottie packages installed (removed Lottie-Dynamic)
- All old code and data deleted
