import SwiftUI

// MARK: - DiceBear Avatar View
// Loads unique illustrated avatars from DiceBear's Open Peeps style API.
// Each character gets a hand-tuned avatar with unique features.

struct AvatarView: View {
    let name: String
    let size: CGFloat
    var isBirthdayBoy: Bool = false
    var showCrown: Bool = false
    
    // MARK: - Per-Character Avatar Configuration
    // Open Peeps by Pablo Stanley — hand-drawn, expressive, great variety
    // Morgan uses a custom Lorelei asset; others use DiceBear Open Peeps

    // Local asset override — used when a custom illustration is provided
    private var localAssetName: String? {
        switch name.lowercased() {
        case "alex": return "avatar-alex"
        case "sam": return "avatar-sam"
        case "jordan": return "avatar-jordan"
        case "riley": return "avatar-riley"
        case "morgan": return "avatar-morgan"
        default: return nil
        }
    }
    
    private var avatarURL: URL? {
        let seed = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let pixelSize = Int(size * 2) // 2x for retina
        var urlString = "https://api.dicebear.com/9.x/open-peeps/png?seed=\(seed)&size=\(pixelSize)"
        
        // Per-character customization
        switch name.lowercased() {
        case "alex":
            // Birthday King: beard + warm skin
            urlString += "&skinColor=9e5622"
            urlString += "&facialHairProbability=100&facialHair=full"
            urlString += "&face=smile"
            urlString += "&accessoriesProbability=0"

        case "sam":
            // The Organizer: glasses
            urlString += "&skinColor=ecad80"
            urlString += "&facialHairProbability=0"
            urlString += "&accessoriesProbability=100&accessories=glasses,glasses2,glasses3,glasses4,glasses5"
            urlString += "&face=smile"

        case "morgan":
            // Stylish look
            urlString += "&skinColor=f2d3b1"
            urlString += "&facialHairProbability=0"
            urlString += "&accessoriesProbability=0"
            urlString += "&face=smile"
            urlString += "&clothingColor=fc909f"

        case "jordan":
            // Clean look
            urlString += "&skinColor=ecad80"
            urlString += "&facialHairProbability=0"
            urlString += "&accessoriesProbability=0"
            urlString += "&face=smile"
            urlString += "&clothingColor=ffeba4"

        case "riley":
            // Clean & simple: warm skin, dark hair
            urlString += "&skinColor=9e5622"
            urlString += "&facialHairProbability=0"
            urlString += "&accessoriesProbability=0"
            urlString += "&face=smile"
            urlString += "&clothingColor=77311d"

        default:
            break
        }
        
        return URL(string: urlString)
    }
    
    var body: some View {
        ZStack {
            if let assetName = localAssetName {
                // Local custom avatar (e.g. Morgan's Lorelei illustration)
                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // DiceBear remote avatar
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
            }
            
            // Crown overlay for birthday boy — sits on top of the circle ring, tilted for fun
            if showCrown && isBirthdayBoy {
                Text("👑")
                    .font(.system(size: size * 0.4))
                    .rotationEffect(.degrees(-15))
                    .offset(x: -(size * 0.08), y: -(size * 0.55))
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
