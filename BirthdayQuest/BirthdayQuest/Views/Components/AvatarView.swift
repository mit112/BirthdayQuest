import SwiftUI

/// Renders a participant's avatar from the bundled catalog.
///
/// Takes an `avatarId`, not a name. The old implementation keyed off `name`, which meant
/// renaming anyone silently changed their face and any unknown name triggered a live HTTP
/// request to api.dicebear.com carrying that name.
///
/// Two call sites (`RewardCardView`, `TimelineNodeView`) have no `avatarId` to hand in —
/// `Reward` and `TimelineEvent` carry only a name. For those, `init(name:size:showsCrown:)`
/// maps the name onto the same bundled catalog via a stable hash, so it never touches the
/// network and always resolves the same face for the same name.
struct AvatarView: View {

    let avatarId: String
    var size: CGFloat = 64
    var showsCrown: Bool = false

    init(avatarId: String, size: CGFloat = 64, showsCrown: Bool = false) {
        self.avatarId = avatarId
        self.size = size
        self.showsCrown = showsCrown
    }

    init(name: String, size: CGFloat = 64, showsCrown: Bool = false) {
        self.avatarId = AvatarCatalog.avatarId(forName: name)
        self.size = size
        self.showsCrown = showsCrown
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(AvatarCatalog.assetName(for: avatarId))
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(
                        BQDesign.Colors.cardBackground,
                        lineWidth: size > 48 ? 3 : 2
                    )
                )

            if showsCrown {
                Text("👑")
                    .font(.system(size: size * 0.32))
                    .offset(x: size * 0.06, y: -size * 0.10)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: BQDesign.Spacing.md) {
        ForEach(AvatarCatalog.all, id: \.self) { id in
            AvatarView(avatarId: id, size: 64, showsCrown: id == AvatarCatalog.all.first)
        }
    }
    .padding()
    .background(BQDesign.Colors.background)
}
