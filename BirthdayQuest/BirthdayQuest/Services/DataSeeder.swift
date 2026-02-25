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
            // EASY — 25 pts
            ["title": "First Bite of NYC", "description": "Eat a dollar slice and rate it honestly", "illustrationAsset": "figure.walk",
             "pointValue": 25, "difficulty": "easy", "submissionType": "photo", "category": "adventure",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Tourist Trap", "description": "Take a classic cringey tourist photo at Times Square", "illustrationAsset": "camera.fill",
             "pointValue": 25, "difficulty": "easy", "submissionType": "photo", "category": "social",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Subway Serenade", "description": "Record yourself vibing to a subway performer", "illustrationAsset": "music.note",
             "pointValue": 25, "difficulty": "easy", "submissionType": "photo", "category": "adventure",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Coffee Snob", "description": "Order the most ridiculous drink at a coffee shop", "illustrationAsset": "cup.and.saucer.fill",
             "pointValue": 25, "difficulty": "easy", "submissionType": "photo", "category": "creative",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Fit Check", "description": "Post your best outfit of the trip", "illustrationAsset": "tshirt.fill",
             "pointValue": 25, "difficulty": "easy", "submissionType": "photo", "category": "social",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            // MEDIUM — 50 pts
            ["title": "Stranger Danger", "description": "Get a photo with a random stranger on the street", "illustrationAsset": "person.2.fill",
             "pointValue": 50, "difficulty": "medium", "submissionType": "photo", "category": "social",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Shot Caller", "description": "Take 3 shots in a row at a bar. No chasers.", "illustrationAsset": "flame.fill",
             "pointValue": 50, "difficulty": "medium", "submissionType": "photo", "category": "physical",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Rooftop King", "description": "Hit a rooftop bar and capture the skyline", "illustrationAsset": "building.2.fill",
             "pointValue": 50, "difficulty": "medium", "submissionType": "photo", "category": "adventure",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Street Food Roulette", "description": "Let a friend pick what you eat from a street vendor. No refusal.", "illustrationAsset": "fork.knife",
             "pointValue": 50, "difficulty": "medium", "submissionType": "photo", "category": "adventure",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "The Negotiator", "description": "Successfully haggle for something in Chinatown", "illustrationAsset": "dollarsign.circle.fill",
             "pointValue": 50, "difficulty": "medium", "submissionType": "photo", "category": "social",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Late Night Slice", "description": "Get pizza after midnight. Must be visibly late and tired.", "illustrationAsset": "moon.stars.fill",
             "pointValue": 50, "difficulty": "medium", "submissionType": "photo", "category": "adventure",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Memory Lane", "description": "Write your favorite memory with each friend on this trip", "illustrationAsset": "heart.fill",
             "pointValue": 50, "difficulty": "medium", "submissionType": "text", "category": "sentimental",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            // HARD — 75 pts
            ["title": "Karaoke King", "description": "Perform a full song at karaoke. Must commit.", "illustrationAsset": "mic.fill",
             "pointValue": 75, "difficulty": "hard", "submissionType": "photo", "category": "creative",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Big Spender", "description": "Buy a round for the whole group at a bar", "illustrationAsset": "creditcard.fill",
             "pointValue": 75, "difficulty": "hard", "submissionType": "button", "category": "social",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "NYC Marathon", "description": "Walk 10,000+ steps in a single day. Screenshot proof.", "illustrationAsset": "figure.run",
             "pointValue": 75, "difficulty": "hard", "submissionType": "photo", "category": "physical",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Heart to Heart", "description": "Have a genuine 1-on-1 conversation with each friend about something real", "illustrationAsset": "heart.text.square.fill",
             "pointValue": 75, "difficulty": "hard", "submissionType": "button", "category": "sentimental",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            // LEGENDARY — 100 pts
            ["title": "The Birthday Speech", "description": "Stand up in public and give a 60-second speech about why you're grateful", "illustrationAsset": "star.fill",
             "pointValue": 100, "difficulty": "hard", "submissionType": "photo", "category": "sentimental",
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
             "teaser": "She actually wrote something nice", "pointCost": 100,
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