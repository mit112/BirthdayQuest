# BirthdayQuest — Rewards & Challenges Update Plan

## Overview
Two changes: (1) Remove video upload from challenge submissions, (2) Build real reward content playback for video, audio, and text.

---

## Part 1: Remove Video Upload + Challenge System Overhaul ✅ COMPLETE (Feb 26)

Video upload was removed earlier. On Feb 26, the entire `submissionType` system was replaced:
- `submissionType` field removed from Challenge model entirely
- Every challenge now shows a universal 3-option tab picker (Photo / Text / Done)
- 2-in-1 challenge support added (`optionBTitle` + `optionBDescription`)
- Seed data replaced with final 12-challenge list from CHALLENGES.md
- Secret Challenge creation simplified (no type picker)

See CHALLENGES.md and CURRENT_STATE.md for full details.

---

## Part 2: Build Reward Content Playback

**Why:** `RewardContentSheet.swift` currently shows placeholders for video and audio. When real content is uploaded, the app needs to actually play it.

**Architecture:** Three content viewers behind a single switch in `RewardContentSheet`. Each viewer is its own focused SwiftUI component.

### New Files:

**1. `Views/Components/VideoPlayerView.swift`**
- Wraps `AVPlayer` in a SwiftUI view using `VideoPlayer` from `AVKit` (iOS 16+, we target 17+)
- Accepts a URL (Firebase Storage download URL)
- Handles: loading state (skeleton/spinner), playback controls (play/pause/scrub), error state
- Sized to fit within the reward sheet (constrained height, rounded corners)
- Auto-plays on appear with a slight delay for dramatic effect (content just unlocked — let it breathe)
- Pauses on disappear to prevent background audio
- No fullscreen mode needed — this is a sentimental moment, not a movie theater
- Uses `AVPlayerItem` status observation for buffering state

**2. `Views/Components/AudioPlayerView.swift`**
- Custom UI (not system player) to match BQDesign aesthetic
- Accepts a URL (Firebase Storage download URL)
- Displays: play/pause button (large, centered), waveform-style progress bar (or simple animated bar), elapsed/total time, sender's name/avatar above
- Uses `AVAudioPlayer` or `AVPlayer` (AVPlayer preferred since it handles remote URLs natively without pre-downloading)
- Activates `AVAudioSession` for playback category so it works with silent mode off
- Animated waveform visual: subtle bars that pulse during playback (not a real waveform — just decorative, timed to playback progress)
- Loading state while buffering

**3. `Views/Components/TextRewardView.swift`**
- Styled card for text messages (replacing the current inline `textContent` in RewardContentSheet)
- Extracted as a standalone component for consistency with the other two
- Large quotation mark decorative element, sender's name, scrollable text body
- Warm background tint, nice typography — this should feel like reading a heartfelt letter

### Modified Files:

**4. `Views/BirthdayBoy/RewardContentSheet.swift`**
- Replace `mediaPlaceholder(icon:label:)` calls with real components
- `case .video:` → `VideoPlayerView(url: contentDownloadURL)`
- `case .audio:` → `AudioPlayerView(url: contentDownloadURL)`
- `case .text:` → `TextRewardView(text: reward.contentText, fromName: reward.fromName)`
- `case .image:` → `AsyncImage` loading from URL with placeholder (bonus, lower priority)
- The URL needs to be a download URL, not a `gs://` path. Two options:
  - **Option A (preferred):** Store the HTTPS download URL directly in Firestore `contentUrl` when uploading rewards. No runtime URL resolution needed.
  - **Option B:** Store `gs://` path, resolve to download URL at runtime via `Storage.storage().reference(forURL:).downloadURL()`. Adds latency on unlock.
  - **We go with Option A.** When I upload the content for you, I'll store the download URL directly.

**5. `Services/FirestoreService.swift`**
- Add a helper method: `getDownloadURL(storagePath:) async throws -> URL` — for any future needs, but with Option A above this is mostly a safety net
- No other service changes needed

**6. `ViewModels/RewardsViewModel.swift`**
- No changes needed. The existing unlock flow already passes the `Reward` object to `RewardContentSheet`. The URL is already in `reward.contentUrl`.

### Content Upload Workflow (when you have the files):

1. You send me the files with the person's name and content type
2. I upload each to Firebase Storage: `/rewards/{rewardId}/{filename}`
3. I grab the download URL from Firebase Storage
4. I update the Firestore reward document:
   - `contentType` → `"video"` / `"audio"` / `"text"`
   - `contentUrl` → HTTPS download URL (for video/audio)
   - `contentText` → the text message (for text rewards)
5. I update the `fromName`, `title`, `teaser`, and `pointCost` as appropriate
6. The app picks it up via the existing real-time listener — no app update needed

### Media Playback Technical Details:

**AVPlayer (Video + Audio):**
- Use `AVPlayer` for both video and audio since it handles remote URLs natively
- Observe `AVPlayerItem.status` for loading/ready/failed states
- Observe `CMTime` for playback progress
- Set `AVAudioSession.sharedInstance().setCategory(.playback)` on app launch to ensure audio works even when silent mode is off
- Call `player.pause()` on view disappear

**Memory management:**
- Create `AVPlayer` instance when view appears, nil it on disappear
- Use `@StateObject` wrapper for the player controller to tie lifecycle to the view
- No caching needed — each reward is viewed maybe 2-3 times total across 4 days

**Error handling:**
- Network timeout → show retry button + friendly message
- Corrupt/missing file → show "Content unavailable" with the sender's name still visible
- Never crash. Never show a blank screen.

### Design Specifications:

All three content viewers follow BQDesign system:

**VideoPlayerView:**
- Rounded corners (BQDesign.Radius.xl)
- Card background behind player
- Soft shadow (BQDesign.Shadows.card)
- Loading: skeleton shimmer in BQDesign.Colors.cardBackground
- Height: ~300pt, aspect-fit within container

**AudioPlayerView:**
- Card-style container with warmGradient tint background
- Large circular play/pause button (BQDesign.Colors.primaryGradient)
- Slim progress bar below (BQDesign.Colors.primaryPurple track)
- Time labels in BQDesign.Typography.caption
- Decorative waveform bars: 20-30 thin rounded rects, animated height

**TextRewardView:**
- Warm background (BQDesign.Colors.goldLight or similar)
- Large decorative " quotation mark (BQDesign.Colors.gold, opacity 0.15, size ~80pt)
- Text in BQDesign.Typography.body, centered
- Sender name below in BQDesign.Typography.caption with BQDesign.Colors.textSecondary
- ScrollView for long messages, max height ~300pt

---

## Implementation Order

1. ~~**Remove video from challenges**~~ ✅ DONE
2. ~~**Build TextRewardView**~~ ✅ DONE
3. ~~**Build AudioPlayerView**~~ ✅ DONE
4. ~~**Build VideoPlayerView**~~ ✅ DONE
5. ~~**Update RewardContentSheet**~~ ✅ DONE
6. ~~**Add AVAudioSession setup**~~ ✅ DONE
7. **Test with real content** — once content is provided

---

## What We Are NOT Changing

- Rewards carousel (already works great)
- Unlock flow / confirmation dialog (already works)
- Points system (already works)
- Timeline event creation on unlock (already works)
- Confetti / haptics on unlock (already works)
- "Check timeline →" button (already works)
- RewardsViewModel (no changes needed)
- Any other screens

---

## Dependencies

- **From you:** Content files from friends/family (video, audio, or text)
- **From me:** Everything else — upload, Firestore setup, all code

---

## Pre-Flight Checklist (before TestFlight)

- [x] All `submissionType: "video"` removed from challenge seed data
- [x] SubmissionType.video case removed from enum
- [x] Hardcoded submissionType removed entirely — universal 3-option picker
- [x] 2-in-1 challenge UI built
- [x] Seed data replaced with final 12-challenge list
- [ ] **Wipe Firestore challenges collection** so new seed data takes effect
- [ ] All reward content uploaded to Firebase Storage
- [ ] All Firestore reward docs updated with real contentType + contentUrl/contentText
- [ ] Video playback tested on real device (Simulator has quirks with AVPlayer)
- [ ] Audio playback tested with silent mode both on and off
- [ ] Text rewards display correctly with varying lengths
- [ ] Unlock → reveal animation → content playback is seamless end-to-end
- [ ] No "TODO: Revert before TestFlight" shortcuts left in code
