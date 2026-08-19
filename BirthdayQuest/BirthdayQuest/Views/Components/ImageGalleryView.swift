import SwiftUI

/// Swipeable image gallery with page indicator dots.
/// Used for rewards that contain multiple images.
struct ImageGalleryView: View {
    
    let urls: [URL]
    let fromName: String
    
    @State private var currentPage = 0
    
    var body: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            // Swipeable images
            TabView(selection: $currentPage) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 350)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous))
                        case .failure:
                            failedPlaceholder
                        default:
                            ProgressView()
                                .tint(BQDesign.Colors.primaryPurple)
                                .frame(maxWidth: .infinity)
                                .frame(height: 350)
                        }
                    }
                    .tag(index)
                    .padding(.horizontal, BQDesign.Spacing.lg)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 370)
            
            // Custom page dots
            HStack(spacing: 8) {
                ForEach(0..<urls.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage
                              ? AnyShapeStyle(BQDesign.Colors.primaryGradient)
                              : AnyShapeStyle(BQDesign.Colors.textTertiary.opacity(0.3)))
                        .frame(width: index == currentPage ? 10 : 7,
                               height: index == currentPage ? 10 : 7)
                        .animation(BQDesign.Animation.snappy, value: currentPage)
                }
            }
            
            // Counter
            Text("\(currentPage + 1) of \(urls.count)")
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textTertiary)
        }
    }
    
    private var failedPlaceholder: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            Image(systemName: "photo")
                .font(.system(size: 30))
                .foregroundColor(BQDesign.Colors.textTertiary)
            Text("Couldn't load image")
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 350)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous)
                .fill(BQDesign.Colors.cardBackground)
        )
    }
}
