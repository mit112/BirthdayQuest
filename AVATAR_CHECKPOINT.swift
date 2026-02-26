// AVATAR CHECKPOINT — Feb 25, 2026
// Save of AvatarView.swift after avatar customization pass.
// Characters: Aaryan=beard+crown, Mit=glasses, Milloni=blue pixie hair, Kashish=headphones overlay+masculine, Gaurav=clean
// Kashish is a GUY. No feminine features.
// Milloni hair fix: forced hair=pixie because seed "Milloni" generates mrClean (bald)
// Backup screenshots in /mnt/user-data/outputs/avatar-backup/

import SwiftUI

// MARK: - DiceBear Avatar View
// Loads unique illustrated avatars from DiceBear's Micah style API.
// Each character gets a hand-tuned avatar with unique features.

struct AvatarView: View {
    let name: String
    let size: CGFloat
    var isBirthdayBoy: Bool = false
    var showCrown: Bool = false
    
    // MARK: - Per-Character Avatar Configuration
    // Each character gets specific DiceBear Micah parameters for a unique look.
    // Features: Aaryan=beard, Mit=glasses, Milloni=blue hair, Kashish=headphones overlay, Gaurav=clean
    
    private var avatarURL: URL? {
        let seed = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let pixelSize = Int(size * 2) // 2x for retina
        var urlString = "https://api.dicebear.com/9.x/micah/png?seed=\(seed)&size=\(pixelSize)"
        
        // Per-character customization
        switch name.lowercased() {
        case "aaryan":
            // Birthday King: beard + confident smirk + warm skin
            urlString += "&mouth=smirk"
            urlString += "&facialHair=beard&facialHairProbability=100&facialHairColor=000000"
            urlString += "&glassesProbability=0"
            urlString += "&eyebrows=up"
            urlString += "&baseColor=ac6651"
            urlString += "&shirtColor=6bd9e9"
            
        case "mit":
            // The Mastermind: glasses + scheming look
            urlString += "&mouth=smile"
            urlString += "&glasses=round&glassesProbability=100&glassesColor=000000"
            urlString += "&facialHairProbability=0"
            urlString += "&eyebrows=up"
            urlString += "&baseColor=f9c9b6"
            urlString += "&shirtColor=9287ff"
            urlString += "&hairColor=000000"
            
        case "milloni":
            // Blue-haired chaos: blue hair + earrings + playful
            // Force pixie hair — seed "Milloni" generates mrClean (bald)
            urlString += "&mouth=laughing"
            urlString += "&hair=pixie&hairColor=4A90D9&hairProbability=100"
            urlString += "&earringsProbability=100&earrings=stud&earringColor=f4d150"
            urlString += "&glassesProbability=0"
            urlString += "&facialHairProbability=0"
            urlString += "&eyebrows=eyelashesUp"
            urlString += "&eyes=smiling"
            urlString += "&baseColor=f9c9b6"
            urlString += "&shirtColor=fc909f"
            urlString += "&eyeShadowColor=d2eff3"
            
        case "kashish":
            // Always has headphones — clean masculine look
            urlString += "&mouth=smile"
            urlString += "&glassesProbability=0"
            urlString += "&facialHairProbability=0"
            urlString += "&earringsProbability=0"
            urlString += "&eyebrows=up"
            urlString += "&baseColor=f9c9b6"
            urlString += "&hairColor=4a2912"
            urlString += "&shirtColor=ffeba4"
            urlString += "&eyes=eyes"
            
        case "gaurav":
            // Clean & simple: fresh, minimal, gym bro energy
            urlString += "&mouth=laughing"
            urlString += "&glassesProbability=0"
            urlString += "&facialHairProbability=0"
            urlString += "&earringsProbability=0"
            urlString += "&eyebrows=up"
            urlString += "&baseColor=ac6651"
            urlString += "&shirtColor=77311d"
            urlString += "&hairColor=000000"
            urlString += "&nose=pointed"
            
        default:
            // Fallback for any unknown character
            urlString += "&mouth=laughing"
        }
        
        return URL(string: urlString)
    }
    
    // Whether this character gets the headphone overlay
    private var showHeadphones: Bool {
        name.lowercased() == "kashish"
    }
    
    var body: some View {
        ZStack {
            AsyncImage(url: avatarURL, transaction: Transaction(animation: .easeIn(duration: 0.3))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackEmoji
                case .empty:
                    ProgressView()
                        .tint(isBirthdayBoy ? BQDesign.Colors.gold : BQDesign.Colors.primaryPurple)
                @unknown default:
                    fallbackEmoji
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            
            // Crown overlay for birthday boy
            if showCrown && isBirthdayBoy {
                Text("👑")
                    .font(.system(size: size * 0.3))
                    .offset(y: -(size * 0.42))
            }
            
            // Headphone overlay for Kashish
            if showHeadphones {
                Text("🎧")
                    .font(.system(size: size * 0.45))
                    .offset(y: -(size * 0.12))
            }
        }
    }
    
    private var fallbackEmoji: some View {
        Text(isBirthdayBoy ? "👑" : "🕵️")
            .font(.system(size: size * 0.45))
            .frame(width: size, height: size)
    }
}

// MARK: - Convenience for character IDs

extension AvatarView {
    /// Create from a BQUser
    init(user: BQUser, size: CGFloat, showCrown: Bool = false) {
        self.name = user.name
        self.size = size
        self.isBirthdayBoy = user.role == .birthdayBoy
        self.showCrown = showCrown
    }
}
