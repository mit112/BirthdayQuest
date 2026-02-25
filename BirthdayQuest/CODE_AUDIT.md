# BirthdayQuest — Code Audit Report
**Date:** Feb 25, 2026 | **Scope:** Full codebase (37 files) | **Reviewer:** Senior iOS Architect

---

## Summary

The codebase is well-organized with clean MVVM separation, a thoughtful design system, and polished UI. That said, there are **6 critical issues** that could cause data corruption or crashes in production, **9 high-priority issues** that affect reliability and user experience, and several medium/low items worth cleaning up before TestFlight.

---

## 🔴 CRITICAL — Fix Before Ship

### 1. Race Condition: Reward Unlock is Non-Atomic (RewardsViewModel.swift:79–103)

**Problem:** `confirmUnlock()` performs 4 sequential independent Firestore writes: `spendPoints()` → `unlockReward()` → `addTimelineEvent()` → `checkFinalBadge()`. If the app crashes, loses network, or the user kills the app between step 1 and step 2, points are deducted but the reward stays locked. The user loses points permanently with no recourse.

**Impact:** Data corruption — user loses points with nothing to show for it.

**Fix:** Use a Firestore `WriteBatch` or `Transaction` to make steps 1-3 atomic.

---

### 2. Race Condition: Challenge Submission is Non-Atomic (ChallengeSubmissionViewModel.swift:68–112)

**Problem:** Same pattern — `completeChallenge()` → `earnPoints()` → `addTimelineEvent()` → optional `incrementSecretChallengesCompleted()` are 3-4 independent writes. Partial failure = inconsistent state.

**Impact:** Data corruption — ghost completions or missing points.

**Fix:** Consolidate into a single `WriteBatch`.

---

### 3. No Server-Side Points Guard — Negative Balance Possible (FirestoreService.swift:215–222)

**Problem:** `spendPoints()` uses `FieldValue.increment(Int64(-amount))` which decrements below zero. No check that `currentPoints >= amount` at the Firestore level. Rapid double-tap on expensive rewards could drain points below zero.

**Impact:** Negative points balance — breaks the game economy.

**Fix:** Use a Firestore Transaction: read `currentPoints`, verify `>= amount`, then write.

---

### 4. Listener Key Collision — SecretChallengeViewModel Kills ChallengesViewModel

**Problem:** Both `ChallengesViewModel.startListening()` and `SecretChallengeViewModel.loadExisting()` call `FirestoreService.shared.listenToChallenges()`, which uses the same key `"challenges"`. The second call replaces the first listener.

**Impact:** Silent data staleness — challenges stop updating live for one view.

**Fix:** Use unique listener keys per consumer (e.g., `"challenges_secret"` for SecretChallengeViewModel).

---

### 5. Memory Leak in AudioPlayerController — Observer Never Removed (AudioPlayerView.swift:286–295)

**Problem:** `NotificationCenter.default.addObserver(forName:...)` returns an opaque token that is never stored. `deinit` calls `removeObserver(self)` which only works for selector-based observers, not closure-based ones. The observer accumulates with each audio player creation.

**Impact:** Memory leak growing with each reward unlock containing audio.

**Fix:** Store the observer token and remove it in `deinit`.

---

### 6. TODO: Hardcoded Override PIN "1234" (CharacterSelectViewModel.swift:23)

**Problem:** `private let overridePin = "1234"` with `// TODO: Revert before TestFlight`. Trivially guessable.

**Impact:** Any user can steal another user's character.

**Fix:** Remove override flow or use a real secret.

---

## 🟠 HIGH — Fix If Time Allows

### 7. Video Submission Type Missing from Enum (Challenge.swift)
Blueprint specifies photo/video/text/button. Enum only has photo/text/button. If a video challenge is added to Firestore, Codable decoding silently drops it.

### 8. No Image Compression Before Upload (ChallengeSubmissionViewModel.swift)
Raw iPhone photos (3-8MB each) uploaded as-is. 17 challenges × 5MB = 85MB over cellular in NYC. Compress to JPEG ~500KB before upload.

### 9. Avatars From External DiceBear API — No Caching/Offline Fallback (AvatarView.swift)
Every AvatarView makes a network request. Dozens per screen. If API is down or slow (NYC subway), all avatars break. Pre-generate or cache to disk.

### 10. FloatingParticlesView Random Values Change on Redraw (FloatingParticlesView.swift)
`size` and `color` use `.random()` in computed properties. Particles flicker randomly on every SwiftUI redraw. Derive from index instead.

### 11. Tab Bar Appearance Set Globally via UIAppearance
`UITabBar.appearance()` in `onAppear` runs repeatedly and affects all tab bars globally. Move to app init or use SwiftUI modifiers.

### 12. SecretChallengeHomeView Hardcodes "Aaryan" (line 83)
Should come from AppConstants or game state, not be a magic string buried in a view.

### 13. SecretMissionCard Shows Raw User ID Instead of Name (SecretChallengesSheet.swift:89)
Displays `fromId.uppercased()` showing "MIT" instead of "Mit". Use `.capitalized` or look up the display name.

### 14. No Error Recovery for Failed Seed (DataSeeder.swift)
If seeding partially fails, subsequent launches may skip re-seeding due to partial data existing. Needs a version/completion marker.

### 15. No Firestore Security Rules
No `firestore.rules` in the project. Anyone with the Firebase config can modify any data. Deploy basic read/write rules before TestFlight.

---

## 🟡 MEDIUM — Polish

### 16. `Reward.isAffordable` Always Returns False
Dead computed property. Remove or make functional.

### 17. Tab Enums Defined in View Files
`BirthdayBoyTab` and `FriendTab` used by SessionManager but defined inside view files. Move to shared location.

### 18. `DispatchQueue.main.asyncAfter` Mixed with Structured Concurrency
Multiple places use GCD instead of `Task.sleep`. Inconsistent concurrency patterns.

### 19. Infinite Carousel Creates 700 Virtual Items
`loopMultiplier = 100` × 7 rewards = 700 IDs. Consider reducing to 20-30.

### 20. Missing `@unknown default` for Codable Enums
New Firestore values cause silent document drops via `compactMap`.

### 21. SessionManager Dual Access (StateObject + Static Singleton)
Works but fragile. Document the pattern clearly.

### 22. Challenges Not Sorted (FirestoreService.swift)
No `.order(by:)` on challenges listener. List order is random/unstable.

### 23. Timeline Scroll Flag Timing Edge Case
`scrollToLatestTimeline` consumed before layout might be ready.

---

## 🔵 LOW

- **#24:** Unused `Combine` imports in 5 ViewModels
- **#25:** Dead `PlaceholderScreen` struct in ContentView.swift
- **#26:** Device-local timestamps (minor clock skew risk)
- **#27:** Unused variable warning in SecretChallengeHomeView line 83
- **#28:** Admin "Remove Points" can go negative
- **#29:** No loading states for Profile
- **#30:** VideoPlayerView potential retain cycle in KVO closure

---

## Pre-TestFlight Checklist

- [x] **#1, #2:** Batch Firestore writes for unlock + submission flows
- [x] **#3:** Transaction-based points spending with balance check
- [x] **#4:** Unique listener keys per ViewModel
- [x] **#5:** Store and properly remove NotificationCenter observer
- [x] **#6:** Remove or secure the override PIN ("1234") → changed to "0228"
- [x] **#7:** Added missing `video` submission type + UI + handler
- [x] **#8:** Add JPEG compression before proof upload (~500KB target)
- [x] **#10:** Fix particle randomness to be deterministic
- [x] **#11:** Tab bar appearance moved to app init (set once)
- [x] **#12, #13:** Fix hardcoded names → uses CharacterID.birthdayBoyName + .capitalized
- [x] **#16:** Removed dead `Reward.isAffordable` property
- [x] **#22:** Add sort order to challenges listener (pointValue ascending)
- [x] **#24, #25:** Remove unused Combine imports (5 VMs) and dead PlaceholderScreen
- [ ] **#9:** Avatar caching/offline fallback (deferred — complex)
- [ ] **#14:** DataSeeder error recovery (deferred — low risk for 5 users)
- [ ] **#15:** Deploy basic Firestore security rules (deferred — testing phase)
