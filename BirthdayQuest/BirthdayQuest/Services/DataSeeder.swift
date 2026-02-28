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
                "avatarId": "king_avatar", "tagline": "Main character energy. Side character track record.",
                "funFacts": ["Least likely to: Meet expectations", "Secret weapon at work: Claude Code", "Real Madrid till death"],
                "roleBadge": "The Birthday King 👑", "claimed": false, "createdAt": Timestamp(date: Date())
            ]),
            (CharacterID.mit, [
                "name": "Mit", "role": UserRole.organizer.rawValue,
                "avatarId": "agent_mit", "tagline": "Will call you at 3am. Will also build you an app.",
                "funFacts": ["Has an anime rec for any mood", "Explained football 100 times. Gets none of it.", "Wannabe coffee enthusiast"],
                "roleBadge": "Secret Agent 🕵️", "claimed": false, "createdAt": Timestamp(date: Date())
            ]),
            (CharacterID.kashish, [
                "name": "Kashish", "role": UserRole.friend.rawValue,
                "avatarId": "agent_kashish", "tagline": "Runs on chai, copium, and vape clouds.",
                "funFacts": ["One Piece is not an anime, it's a lifestyle", "Claims he doesn't cook. Trader Joe's loyalty member.", "Arsenal supporter (pain is familiar)"],
                "roleBadge": "Secret Agent 🕵️", "claimed": false, "createdAt": Timestamp(date: Date())
            ]),
            (CharacterID.gaurav, [
                "name": "Gaurav", "role": UserRole.friend.rawValue,
                "avatarId": "agent_gaurav", "tagline": "Dodges group trips like it's cardio.",
                "funFacts": ["His phone only receives texts, apparently", "Always down for garba", "Abs by Halloween (always the next one)"],
                "roleBadge": "Secret Agent 🕵️", "claimed": false, "createdAt": Timestamp(date: Date())
            ]),
            (CharacterID.milloni, [
                "name": "Milloni", "role": UserRole.friend.rawValue,
                "avatarId": "agent_milloni", "tagline": "Her gifts have lore AND perfect wrapping?!",
                "funFacts": ["Went from 'no thanks' to 'what are we drinking?'", "Thinks Seattle is a personality trait", "Will cook you the best meals"],
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
            ["title": "Method Actor Type Shii", "description": "Your friends pick a persona and accent for you. Maintain it through an entire restaurant order — appetizers, drinks, dessert, all of it. Break character and it doesn't count.", "illustrationAsset": "theatermasks.fill",
             "pointValue": 35, "difficulty": "easy", "category": "social",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Trust Fall for Your Stomach", "description": "Each friend picks one menu item for you — no vetoes, no swaps. You love fine dining? Let's see you fine dine something you didn't choose.", "illustrationAsset": "fork.knife",
             "pointValue": 35, "difficulty": "easy", "category": "adventure",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now,
             "optionBTitle": "Waiter's Choice", "optionBDescription": "Walk into a restaurant and tell the waiter to order your entire meal. Appetizer, main, dessert — their call. A true foodie trusts the chef."],
            ["title": "Compliment Roast", "description": "Give each friend a compliment that's secretly a devastating roast. They have to say 'thank you' with a straight face. You roast yourself daily — time to weaponize that energy on everyone else.", "illustrationAsset": "flame.fill",
             "pointValue": 35, "difficulty": "easy", "category": "social",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            // MEDIUM — 50 pts
            ["title": "Phone Roulette", "description": "Your friends scroll through your recent texts and pick a contact. You call them on speaker for 60 seconds — no hanging up, no explaining. This is your come-up arc, right? Time to reconnect with people you've been ghosting.", "illustrationAsset": "phone.fill",
             "pointValue": 50, "difficulty": "medium", "category": "social",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "The Aaryan Cinematic Universe", "description": "Do an impression of every friend at the table. Each one rates you 1-10.", "illustrationAsset": "person.2.fill",
             "pointValue": 50, "difficulty": "medium", "category": "creative",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Déjà Vu, But Make It NYC", "description": "Pick a memorable photo from the group's history and recreate it right here. Side-by-side comparison is the proof. Bonus respect if you pick an embarrassing one.", "illustrationAsset": "camera.fill",
             "pointValue": 50, "difficulty": "medium", "category": "creative",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "Stranger Photo", "description": "Convince a complete stranger in NYC to take a photo with you. No context, no explanation. Just vibes and confidence.", "illustrationAsset": "person.crop.rectangle.stack.fill",
             "pointValue": 50, "difficulty": "medium", "category": "adventure",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now,
             "optionBTitle": "Make a New Friend", "optionBDescription": "Introduce yourself to a stranger. Have a real conversation — 5 minutes minimum, learn their name, what they do, something real. Then get the photo."],
            ["title": "Can't Sing for Shit: The Concert", "description": "Your friends pick the song. You perform it with full commitment — no half-assing, no laughing through it. You already tell everyone you can't sing. Now prove it on stage.", "illustrationAsset": "mic.fill",
             "pointValue": 60, "difficulty": "medium", "category": "creative",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now,
             "optionBTitle": "Stranger Duet", "optionBDescription": "Find a stranger at karaoke and convince them to duet with you. Friends still pick the song. Can you get someone else to suffer with you?"],
            ["title": "Letter to 30-Year-Old You", "description": "Handwrite a letter to open on your 30th birthday. Seal it in front of the group.", "illustrationAsset": "envelope.fill",
             "pointValue": 50, "difficulty": "medium", "category": "sentimental",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now,
             "optionBTitle": "Time Capsule Video", "optionBDescription": "Record a video message to your future self — where you are, what you feel, predictions."],
            // HARD — 75 pts
            ["title": "King's Address", "description": "At the actual birthday dinner, stand up and give a toast. Funny, heartfelt, whatever feels right.", "illustrationAsset": "wineglass.fill",
             "pointValue": 75, "difficulty": "hard", "category": "sentimental",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            ["title": "First Time for Everything", "description": "Open-ended. Food, activity, experience — anything genuinely new. Proof: photo + text description of what it was.", "illustrationAsset": "sparkles",
             "pointValue": 75, "difficulty": "hard", "category": "adventure",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            // LEGENDARY — 100 pts
            ["title": "No Cap, Just Heart", "description": "Genuine heartfelt toast to each friend individually. Specific memories, why they matter. No jokes.", "illustrationAsset": "heart.fill",
             "pointValue": 100, "difficulty": "hard", "category": "sentimental",
             "isSecret": false, "isDelivered": false, "isCompleted": false, "createdAt": now],
            // PASSIVE — 50 pts
            ["title": "No Stuti Weekend", "description": "Zero mentions, zero texts, zero stalking socials. The whole weekend is a Stuti-free zone. Friends are watching. Every slip-up gets called out. This is YOUR birthday — act like it.", "illustrationAsset": "hand.raised.slash.fill",
             "pointValue": 50, "difficulty": "medium", "category": "social",
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
            // Audio tier: 50 pts
            ["fromUserId": CharacterID.mit, "fromName": "Mit", "title": "A message from Mit",
             "teaser": "The mastermind has something to say", "pointCost": 50,
             "contentType": "audio",
             "isUnlocked": false, "sortOrder": 1, "badgeIllustration": "heart_badge", "createdAt": now],
            // Video tier: 100 pts each
            ["fromUserId": CharacterID.kashish, "fromName": "Kashish", "title": "A message from Kashish",
             "teaser": "He actually wrote something nice", "pointCost": 100,
             "contentType": "video",
             "isUnlocked": false, "sortOrder": 2, "badgeIllustration": "heart_badge", "createdAt": now],
            ["fromUserId": CharacterID.gaurav, "fromName": "Gaurav", "title": "A message from Gaurav",
             "teaser": "He actually sat down and recorded this", "pointCost": 100,
             "contentType": "video",
             "isUnlocked": false, "sortOrder": 3, "badgeIllustration": "heart_badge", "createdAt": now],
            ["fromUserId": CharacterID.milloni, "fromName": "Milloni", "title": "A message from Milloni",
             "teaser": "Chaos coordinator gets sentimental", "pointCost": 100,
             "contentType": "video",
             "isUnlocked": false, "sortOrder": 4, "badgeIllustration": "heart_badge", "createdAt": now],
            ["fromName": "Family", "title": "A surprise from the family",
             "teaser": "The whole family got together for this", "pointCost": 100,
             "contentType": "video",
             "isUnlocked": false, "sortOrder": 5, "badgeIllustration": "star_badge", "createdAt": now],
            ["fromName": "Abhishek", "title": "A message from Abhishek",
             "teaser": "He's got something to say", "pointCost": 100,
             "contentType": "video",
             "isUnlocked": false, "sortOrder": 6, "badgeIllustration": "heart_badge", "createdAt": now],
            ["fromName": "Manan", "title": "A message from Manan",
             "teaser": "He's got something to say", "pointCost": 100,
             "contentType": "video",
             "isUnlocked": false, "sortOrder": 7, "badgeIllustration": "heart_badge", "createdAt": now],
            ["fromName": "Jay", "title": "A message from Jay",
             "teaser": "He's got something to say", "pointCost": 100,
             "contentType": "video",
             "isUnlocked": false, "sortOrder": 8, "badgeIllustration": "heart_badge", "createdAt": now],
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