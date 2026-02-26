import Foundation
import FirebaseFirestore

// MARK: - Data Seeder
// Populates Firestore with initial data.
// Checks each collection independently so new content can be added.

struct DataSeeder {
    
    private static let db = Firestore.firestore()
    
    // MARK: - Seed All
    
    static func seedIfNeeded() async {
        do {
            // Users + game state (original seed)
            let gsDoc = try await db.collection(Collections.gameState)
                .document(Collections.gameStateDoc).getDocument()
            if !gsDoc.exists {
                print("🌱 Seeding users + game state...")
                try await seedUsers()
                try await seedGameState()
            }
            
            // Challenges — check for regular (non-secret) challenges specifically
            let challengeSnap = try await db.collection(Collections.challenges)
                .whereField("isSecret", isEqualTo: false).limit(to: 1).getDocuments()
            if challengeSnap.documents.isEmpty {
                print("🌱 Seeding challenges...")
                try await seedChallenges()
            }
            
            // Rewards
            let rewardSnap = try await db.collection(Collections.rewards).limit(to: 1).getDocuments()
            if rewardSnap.documents.isEmpty {
                print("🌱 Seeding rewards...")
                try await seedRewards()
            }
            
            print("✅ Firestore ready")
        } catch {
            print("❌ Seed error: \(error.localizedDescription)")
        }
    }    
    // MARK: - Seed Users
    
    private static func seedUsers() async throws {
        let users: [(id: String, data: [String: Any])] = [
            (CharacterID.aaryan, [
                "name": "Aaryan", "role": UserRole.birthdayBoy.rawValue,
                "avatarId": "king_avatar", "tagline": "Ferrari fan, forever depressed",
                "funFacts": ["Favorite excuse: 'I'm on my way'", "Most likely to: show up 45 minutes late", "Spirit animal: a raccoon at 3am"],
                "roleBadge": "The Birthday King 👑", "claimed": false, "createdAt": Timestamp(date: Date())
            ]),
            (CharacterID.mit, [
                "name": "Mit", "role": UserRole.organizer.rawValue,
                "avatarId": "agent_mit", "tagline": "The mastermind behind the curtain",
                "funFacts": ["Favorite move: pulling strings from the shadows", "Most likely to: have a spreadsheet for everything", "Spirit animal: an owl with a clipboard"],
                "roleBadge": "Secret Agent 🕵️", "claimed": false, "createdAt": Timestamp(date: Date())
            ]),
            (CharacterID.kashish, [
                "name": "Kashish", "role": UserRole.friend.rawValue,
                "avatarId": "agent_kashish", "tagline": "Will judge your outfit before saying hi",
                "funFacts": ["Favorite hobby: unsolicited fashion advice", "Most likely to: take 40 minutes to get ready", "Spirit animal: a peacock with opinions"],
                "roleBadge": "Secret Agent 🕵️", "claimed": false, "createdAt": Timestamp(date: Date())
            ]),
            (CharacterID.gaurav, [
                "name": "Gaurav", "role": UserRole.friend.rawValue,
                "avatarId": "agent_gaurav", "tagline": "Gym bro energy, snack drawer reality",
                "funFacts": ["Favorite lie: 'I'll just have one drink'", "Most likely to: disappear and be found eating", "Spirit animal: a golden retriever at a buffet"],
                "roleBadge": "Secret Agent 🕵️", "claimed": false, "createdAt": Timestamp(date: Date())
            ]),
            (CharacterID.milloni, [
                "name": "Milloni", "role": UserRole.friend.rawValue,
                "avatarId": "agent_milloni", "tagline": "Chaos coordinator extraordinaire",
                "funFacts": ["Favorite vibe: controlled chaos", "Most likely to: suggest something unhinged at 2am", "Spirit animal: a caffeinated squirrel"],
                "roleBadge": "Secret Agent 🕵️", "claimed": false, "createdAt": Timestamp(date: Date())
            ])
        ]
        let batch = db.batch()
        for user in users {
            batch.setData(user.data, forDocument: db.collection(Collections.users).document(user.id))
        }
        try await batch.commit()
        print("  → 5 characters seeded")
    }    
    // MARK: - Seed Challenges
    
    private static func seedChallenges() async throws {
        let now = Timestamp(date: Date())
        let challenges: [[String: Any]] = [
            // EASY — 35 pts
            ["title": "Order in Character", "description": "Friends pick a persona/accent. Maintain it through an entire restaurant order.", "illustrationAsset": "theatermasks.fill",
             "pointValue": 35, "difficulty": "easy", "category": "social",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Blind Menu Roulette", "description": "Each friend picks a menu item, spin a roulette wheel, eat whatever it lands on.", "illustrationAsset": "fork.knife",
             "pointValue": 35, "difficulty": "easy", "category": "adventure",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now,
             "optionBTitle": "Waiter's Choice", "optionBDescription": "Let the waiter choose the entire meal for you. No complaints allowed."],
            ["title": "Compliment Roast", "description": "Give each friend a compliment that's secretly a roast. They must say 'thank you'.", "illustrationAsset": "flame.fill",
             "pointValue": 35, "difficulty": "easy", "category": "social",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            // MEDIUM — 50 pts
            ["title": "Phone Roulette", "description": "Friends scroll your recent texts/calls and pick someone. Call on speaker for 60 seconds.", "illustrationAsset": "phone.fill",
             "pointValue": 50, "difficulty": "medium", "category": "social",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Impression Gauntlet", "description": "Do an impression of each friend at the table. Each rates 1-10.", "illustrationAsset": "person.2.fill",
             "pointValue": 50, "difficulty": "medium", "category": "creative",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Recreate an Iconic Photo", "description": "Recreate a memorable photo — childhood pic, classic group shot, old screenshot. Side-by-side comparison is the proof.", "illustrationAsset": "camera.fill",
             "pointValue": 50, "difficulty": "medium", "category": "creative",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Stranger Photo", "description": "Convince a random stranger to take a photo with you.", "illustrationAsset": "person.crop.rectangle.stack.fill",
             "pointValue": 50, "difficulty": "medium", "category": "adventure",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now,
             "optionBTitle": "Make a New Friend", "optionBDescription": "Introduce yourself to strangers, have a real 5+ min conversation, then get the photo."],
            ["title": "Karaoke Roulette", "description": "Friends pick the song. Perform with full commitment.", "illustrationAsset": "mic.fill",
             "pointValue": 60, "difficulty": "medium", "category": "creative",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now,
             "optionBTitle": "Stranger Duet", "optionBDescription": "Find a stranger at karaoke, convince them to duet. Friends still pick the song."],
            ["title": "Letter to 30-Year-Old You", "description": "Handwrite a letter to open on your 30th birthday. Seal it in front of the group.", "illustrationAsset": "envelope.fill",
             "pointValue": 50, "difficulty": "medium", "category": "sentimental",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now,
             "optionBTitle": "Time Capsule Video", "optionBDescription": "Record a video message to your future self — where you are, what you feel, predictions."],
            // HARD — 75 pts
            ["title": "Birthday Dinner Toast", "description": "At the actual birthday dinner, stand up and give a toast. Funny, heartfelt, whatever feels right.", "illustrationAsset": "wineglass.fill",
             "pointValue": 75, "difficulty": "hard", "category": "sentimental",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Try Something You've Never Done", "description": "Open-ended. Food, activity, experience — anything genuinely new. Proof: photo + text description of what it was.", "illustrationAsset": "sparkles",
             "pointValue": 75, "difficulty": "hard", "category": "adventure",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            // LEGENDARY — 100 pts
            ["title": "The Real Toast", "description": "Genuine heartfelt toast to each friend individually. Specific memories, why they matter. No jokes.", "illustrationAsset": "heart.fill",
             "pointValue": 100, "difficulty": "hard", "category": "sentimental",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
        ]
        
        let batch = db.batch()
        for challenge in challenges {
            let ref = db.collection(Collections.challenges).document()
            batch.setData(challenge, forDocument: ref)
        }
        try await batch.commit()
        
        // Update game_state totals
        try await db.collection(Collections.gameState).document(Collections.gameStateDoc).updateData([
            "totalChallenges": challenges.count, "updatedAt": Timestamp(date: Date())
        ])
        print("  → \(challenges.count) challenges seeded")
    }    
    // MARK: - Seed Rewards
    
    private static func seedRewards() async throws {
        let now = Timestamp(date: Date())
        let rewards: [[String: Any]] = [
            ["fromUserId": CharacterID.mit, "fromName": "Mit", "title": "A message from Mit",
             "teaser": "The mastermind has something to say", "pointCost": 100,
             "contentType": "text", "contentText": "Placeholder — real content coming soon",
             "isUnlocked": false, "sortOrder": 1, "badgeIllustration": "heart_badge", "createdAt": now],
            ["fromUserId": CharacterID.kashish, "fromName": "Kashish", "title": "A message from Kashish",
             "teaser": "He actually wrote something nice", "pointCost": 100,
             "contentType": "text", "contentText": "Placeholder — real content coming soon",
             "isUnlocked": false, "sortOrder": 2, "badgeIllustration": "heart_badge", "createdAt": now],
            ["fromUserId": CharacterID.gaurav, "fromName": "Gaurav", "title": "A message from Gaurav",
             "teaser": "Between snacks, he found the words", "pointCost": 100,
             "contentType": "text", "contentText": "Placeholder — real content coming soon",
             "isUnlocked": false, "sortOrder": 3, "badgeIllustration": "heart_badge", "createdAt": now],
            ["fromUserId": CharacterID.milloni, "fromName": "Milloni", "title": "A message from Milloni",
             "teaser": "Chaos coordinator gets sentimental", "pointCost": 100,
             "contentType": "text", "contentText": "Placeholder — real content coming soon",
             "isUnlocked": false, "sortOrder": 4, "badgeIllustration": "heart_badge", "createdAt": now],
            ["fromName": "Mom", "title": "A message from Mom",
             "teaser": "You'll want to sit down for this", "pointCost": 125,
             "contentType": "text", "contentText": "Placeholder — real content coming soon",
             "isUnlocked": false, "sortOrder": 5, "badgeIllustration": "heart_badge", "createdAt": now],
            ["fromName": "Dad", "title": "A message from Dad",
             "teaser": "He doesn't say this often", "pointCost": 125,
             "contentType": "text", "contentText": "Placeholder — real content coming soon",
             "isUnlocked": false, "sortOrder": 6, "badgeIllustration": "heart_badge", "createdAt": now],
            ["fromName": "Family", "title": "A surprise from the family",
             "teaser": "They all got together for this one", "pointCost": 150,
             "contentType": "text", "contentText": "Placeholder — real content coming soon",
             "isUnlocked": false, "sortOrder": 7, "badgeIllustration": "star_badge", "createdAt": now],
        ]
        
        let batch = db.batch()
        for reward in rewards {
            let ref = db.collection(Collections.rewards).document()
            batch.setData(reward, forDocument: ref)
        }
        try await batch.commit()
        
        // Update game_state totals
        try await db.collection(Collections.gameState).document(Collections.gameStateDoc).updateData([
            "totalRewards": rewards.count, "updatedAt": Timestamp(date: Date())
        ])
        print("  → \(rewards.count) rewards seeded")
    }    
    // MARK: - Seed Game State
    
    private static func seedGameState() async throws {
        let data: [String: Any] = [
            "birthdayBoyId": CharacterID.birthdayBoy,
            "totalPointsEarned": 0, "totalPointsSpent": 0, "currentPoints": 0,
            "challengesCompleted": 0, "totalChallenges": 0,
            "secretChallengesFound": 0, "secretChallengesCompleted": 0,
            "rewardsUnlocked": 0, "totalRewards": 0,
            "allRewardsUnlocked": false, "finalBadgeUnlocked": false,
            "gameStartedAt": Timestamp(date: Date()), "currentDay": 1,
            "updatedAt": Timestamp(date: Date())
        ]
        try await db.collection(Collections.gameState)
            .document(Collections.gameStateDoc).setData(data)
        print("  → game_state/main seeded")
    }
}