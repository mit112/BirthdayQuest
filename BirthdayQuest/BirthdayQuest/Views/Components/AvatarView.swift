import SwiftUI

// MARK: - DiceBear Avatar View
// Loads unique illustrated avatars from DiceBear's Micah style API.
// Each character gets a consistent avatar based on their name as seed.

struct AvatarView: View {
    let name: String
    let size: CGFloat
    var isBirthdayBoy: Bool = false
    var showCrown: Bool = false
    
    // DiceBear Micah style — colorful, playful, Duolingo-like
    private var avatarURL: URL? {
        let seed = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let pixelSize = Int(size * 2) // 2x for retina
        return URL(string: "https://api.dicebear.com/9.x/micah/png?seed=\(seed)&size=\(pixelSize)")
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