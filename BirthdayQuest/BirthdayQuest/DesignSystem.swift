import SwiftUI

// MARK: - BirthdayQuest Design System
// "Headspace meets Duolingo" — warm, playful, layered, alive.

enum BQDesign {
    
    // MARK: - Color Palette
    
    enum Colors {
        // Primary gradient — the signature look
        static let primaryPurple = Color(hex: "7C5CFC")
        static let primaryPink = Color(hex: "FF6B9D")
        static let primaryOrange = Color(hex: "FFA45B")
        
        // Warm neutrals
        static let background = Color(hex: "FBF7F4")
        static let cardBackground = Color.white
        static let surfaceElevated = Color(hex: "FFFFFF")
        
        // Text hierarchy
        static let textPrimary = Color(hex: "2D2B3D")
        static let textSecondary = Color(hex: "8E8AA0")
        static let textTertiary = Color(hex: "B8B5C6")
        
        // Accents
        static let gold = Color(hex: "F5A623")
        static let goldLight = Color(hex: "FFF3DC")
        static let success = Color(hex: "4CD964")
        static let challengeBlue = Color(hex: "5B9FE6")
        static let secretDark = Color(hex: "1A1A2E")
        static let secretAccent = Color(hex: "E94560")
        
        // Points
        static let pointsGold = Color(hex: "F5A623")
        
        // Gradients
        static let primaryGradient = LinearGradient(
            colors: [primaryPurple, primaryPink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let warmGradient = LinearGradient(
            colors: [primaryPink, primaryOrange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let goldGradient = LinearGradient(
            colors: [Color(hex: "F5A623"), Color(hex: "FFC857")],
            startPoint: .top,
            endPoint: .bottom
        )
        
        static let secretGradient = LinearGradient(
            colors: [Color(hex: "1A1A2E"), Color(hex: "16213E")],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Typography
    
    enum Typography {
        static let heroTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let screenTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        static let sectionTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let cardTitle = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 16, weight: .regular, design: .rounded)
        static let bodyBold = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let caption = Font.system(size: 14, weight: .medium, design: .rounded)
        static let captionSmall = Font.system(size: 12, weight: .medium, design: .rounded)
        static let points = Font.system(size: 20, weight: .bold, design: .rounded)
        static let pointsLarge = Font.system(size: 36, weight: .heavy, design: .rounded)
        static let tagline = Font.system(size: 15, weight: .medium, design: .serif)
    }
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    // MARK: - Corner Radius
    
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let pill: CGFloat = 999
    }
    
    // MARK: - Shadows
    
    enum Shadows {
        static let card = Shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        static let cardHover = Shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 8)
        static let glow = Shadow(color: Colors.primaryPurple.opacity(0.3), radius: 16, x: 0, y: 4)
    }
    
    // MARK: - Animation
    
    enum Animation {
        static let snappy = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.75)
        static let smooth = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.8)
        static let bouncy = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.6)
        static let gentle = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.6)
    }
    
    // MARK: - Haptics
    
    enum Haptics {
        static func light() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        static func medium() {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        static func heavy() {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        static func success() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        static func error() {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        static func selection() {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

// MARK: - Shadow Helper

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}
