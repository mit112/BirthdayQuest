# BirthdayQuest — Challenge Decisions

## Final Challenge List (12 regular + 4 secret from friends)

All challenges visible from day one. Order in list suggests arc (fun → social → emotional) but player picks freely.

### Challenge 1: Order in Character
- Friends pick a persona/accent, Aaryan maintains it through entire restaurant order
- Category: social | Difficulty: easy | Points: 25-50

### Challenge 2: Blind Menu Roulette / Waiter's Choice ⚡ 2-in-1
- Option A: Each friend picks a menu item, spin a roulette wheel, eat whatever it lands on
- Option B: Let the waiter choose the entire meal
- Category: food | Difficulty: easy | Points: 25-50

### Challenge 3: Compliment Roast
- Give each friend a compliment that's secretly a roast. They must say "thank you"
- Category: social | Difficulty: easy | Points: 25-50

### Challenge 4: Phone Roulette (modified)
- Friends scroll recent texts/calls (not full contacts) and pick someone. Call on speaker for 60 seconds
- Alternative: friends pick a category (college friend, someone you haven't talked to in 6mo, etc.)
- Category: social | Difficulty: medium | Points: 50-75

### Challenge 5: Impression Gauntlet
- Do an impression of each friend at the table. Each rates 1-10
- Category: creative | Difficulty: medium | Points: 50-75

### Challenge 6: The Real Toast 🔒 LATE-GAME
- Genuine heartfelt toast to each friend individually. Specific memories, why they matter. No jokes
- Positioned as one of the last challenges before final badge unlock
- Category: sentimental | Difficulty: hard | Points: 75-100

### Challenge 7: Recreate an Iconic Photo
- Recreate a memorable photo — childhood pic, classic group shot, old screenshot
- Can be with the group or one specific friend. Side-by-side comparison is the proof
- Category: creative | Difficulty: easy | Points: 25-50

### Challenge 8: Stranger Photo / Make a New Friend ⚡ 2-in-1
- Option A: Convince a random stranger to take a photo with you
- Option B: Introduce yourself to strangers, have a real 5+ min conversation, then get the photo
- Category: social/adventure | Difficulty: medium | Points: 50-75

### Challenge 9: Karaoke Roulette / Stranger Duet ⚡ 2-in-1
- Option A: Friends pick the song, perform with full commitment
- Option B: Find a stranger at karaoke, convince them to duet. Friends still pick the song
- Category: creative | Difficulty: medium-hard | Points: 50-100

### Challenge 10: Letter to 30-Year-Old You / Time Capsule Video ⚡ 2-in-1
- Option A: Handwrite a letter to open on 30th birthday. Seal in front of group
- Option B: Record a video message to future self — where you are, what you feel, predictions
- Category: sentimental | Difficulty: medium | Points: 50-75

### Challenge 11: Birthday Dinner Toast
- At the actual birthday dinner, stand up and give a toast. Funny, heartfelt, whatever feels right
- Category: sentimental | Difficulty: medium | Points: 50-75

### Challenge 12: Try Something You've Literally Never Done
- Open-ended. Food, activity, experience — anything genuinely new
- Proof: photo + text description of what it was and why it's a first
- Category: adventure | Difficulty: hard | Points: 75-100

### Secret Challenges (4 total — one from each friend)
- Created by Mit, Kashish, Gaurav, Milloni via the app's Secret Challenge screen
- All use the same universal submission (photo/text/completed)

---

## Design Patterns

### 2-in-1 Cards ✅ IMPLEMENTED (Feb 26)
4 challenges use this: Menu Roulette, Stranger Photo, Karaoke Roulette, Letter/Time Capsule.

**How it works:** Challenge model has optional `optionBTitle` + `optionBDescription` fields. `isTwoInOne` computed property checks if optionBTitle is non-nil. ChallengeDetailView shows Option A / Option B toggle tabs that swap the displayed title + description. ChallengeCardView shows an orange ⚡ "2-in-1" badge in metadata row.

This is a **UI-only** feature — one challenge doc in Firestore, the detail view just presents two flavors visually. No tracking which option he picked.

### Universal Submission Type ✅ IMPLEMENTED (Feb 26)
`submissionType` removed from Challenge model. Every challenge now shows a 3-option tab picker in ChallengeDetailView (Photo / Text / Done). Player picks whichever fits the moment. Secret Challenge creation no longer has a submission type picker.

**Files changed:**
- `Models/Challenge.swift` — removed `submissionType` property, added custom decoder
- `Views/BirthdayBoy/ChallengeDetailView.swift` — universal 3-tab submission picker
- `ViewModels/ChallengeSubmissionViewModel.swift` — `selectedSubmissionType` state drives submission
- `Views/Friend/SecretChallengeHomeView.swift` — removed submission type picker
- `ViewModels/SecretChallengeViewModel.swift` — removed submissionType from save/create
- `Views/BirthdayBoy/SecretChallengesSheet.swift` — replaced submissionType icon with chevron
- `Views/BirthdayBoy/ChallengeCardView.swift` — shows 2-in-1 badge instead of submission type icon
- `Services/DataSeeder.swift` — removed submissionType from all seed data

### Suggested Visual Order in App
**Top (fun/easy):** Order in Character, Compliment Roast, Menu Roulette, Impression Gauntlet
**Middle (social/adventure):** Phone Roulette, Stranger Photo, Karaoke, Try Something New
**Bottom (sentimental):** Recreate Photo, Letter/Time Capsule, Birthday Toast, The Real Toast

### Point Budget
- Total available from regular challenges: ~700-900 pts
- Total from secret challenges: ~100-400 pts (friends set 25-100 each)
- Grand total available: ~800-1300 pts
- Rewards should be priced so completing ~60-70% of challenges unlocks all rewards

---

## Personalization Phase (TODO)
These 12 challenges are the structure. Next step: personalize them with Aaryan-specific details:
- Inside jokes in challenge descriptions
- Specific photos to recreate
- Specific people to call in Phone Roulette categories
- Custom illustration/emoji per challenge
- Fun challenge titles that reference group humor
