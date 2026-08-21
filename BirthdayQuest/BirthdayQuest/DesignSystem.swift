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
        
        // Text hierarchy.
        //
        // Ratios below are against `background` (#FBF7F4); on `cardBackground` each is slightly
        // higher, so the app background is the binding case. WCAG AA needs 4.5:1 for body text
        // and 3:1 for large text.
        static let textPrimary = Color(hex: "2D2B3D")     // 12.93:1 — any size
        static let textSecondary = Color(hex: "6B6880")   // 5.03:1  — any size

        /// **Not a text colour.** 1.88:1 against the app background — it fails AA for body *and*
        /// large text, so it may only tint decoration: divider rules, skeleton fills, page dots,
        /// progress tracks. Anything a user has to read takes `textSecondary` instead, which is
        /// the lightest token that clears AA. Kept light on purpose, because that is exactly what
        /// makes it right for a 15%-opacity skeleton block and wrong for a sentence.
        static let textTertiary = Color(hex: "B8B5C6")
        
        // Accents.
        //
        // `gold` and `success` are 1.90:1 and 1.73:1 on the light backgrounds and 8.42:1 and
        // 9.27:1 on `secretDark` — they carry text only on a dark surface. On a light one they
        // are for fills, glyphs and badges, with the sentence itself left at `textPrimary`.
        static let gold = Color(hex: "F5A623")

        /// `gold` for text on a *light* surface, where `gold` itself is 1.90:1 and illegible.
        /// Same hue (37deg) and saturation, dropped in lightness until it clears AA body text —
        /// 4.65:1 on the app background, 4.95:1 on a card. Use it for point values and earned
        /// totals; keep `gold` for the fills, glyphs and badges beside them, so the accent
        /// survives while the number stays readable.
        static let goldText = Color(hex: "9C6407")

        static let goldLight = Color(hex: "FFF3DC")
        static let success = Color(hex: "4CD964")
        static let challengeBlue = Color(hex: "5B9FE6")
        static let secretDark = Color(hex: "1A1A2E")
        static let secretAccent = Color(hex: "E94560")

        // Semantic.
        //
        // 3.59:1 — large text and UI only, never a body sentence. The error rows across the
        // occasion, create, join and host-panel surfaces put this on the *icon* and leave the
        // sentence at `textPrimary`; copy that split rather than tinting the text.
        static let error = Color(hex: "E94560")

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
    
    /// Every token is a *semantic text style*, never a fixed point size, so all of them track the
    /// user's Dynamic Type setting. `Font.system(size:)` cannot do that and the user cannot
    /// override it, which is why no token may reintroduce one.
    ///
    /// The style was chosen to land on each token's former point size wherever a style matched it
    /// exactly (8 of 11 did, at the default content size). The other three shift by at most 2pt:
    /// `cardTitle` 18 -> 17 (`.headline`, whose intrinsic semibold matches the old weight),
    /// `caption` 14 -> 13, and `pointsLarge` 36 -> 34.
    enum Typography {
        static let heroTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let screenTitle = Font.system(.title, design: .rounded, weight: .bold)
        static let sectionTitle = Font.system(.title2, design: .rounded, weight: .semibold)
        static let cardTitle = Font.system(.headline, design: .rounded)
        static let body = Font.system(.callout, design: .rounded)
        static let bodyBold = Font.system(.callout, design: .rounded, weight: .semibold)
        static let caption = Font.system(.footnote, design: .rounded, weight: .medium)
        static let captionSmall = Font.system(.caption, design: .rounded, weight: .medium)
        static let points = Font.system(.title3, design: .rounded, weight: .bold)
        static let pointsLarge = Font.system(.largeTitle, design: .rounded, weight: .heavy)
        static let tagline = Font.system(.subheadline, design: .serif, weight: .medium)
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

// MARK: - Motion Gating

/// How much *decorative* motion the current environment allows.
///
/// The precedence order is fixed and one-way: `accessibilityReduceMotion` is tier 1 and always
/// wins, Low Power Mode is tier 2 and only gets a vote if tier 1 passed, and the design's own
/// preference is tier 3. It is derived in exactly one place — `resolve(reduceMotion:lowPower:)`,
/// reached through `\.bqMotionLevel` — so that no view can re-litigate it. That matters more here
/// than it would elsewhere: every animation this gates is `repeatForever`, so one view that
/// skipped the check would animate at the user *forever*, not for a moment.
nonisolated enum MotionLevel: Equatable {
    /// Reduce Motion is on. No decorative motion at all.
    case none
    /// Low Power Mode, without Reduce Motion. One-shot transitions are fine; nothing perpetual.
    case minimal
    /// No constraint. The design's preference applies.
    case full

    /// Whether a perpetual (`repeatForever`) decoration may run. Only `.full` permits one — a
    /// pulse that never stops is the exact thing both a vestibular disorder and a dying battery
    /// need relief from, so `.minimal` withholds it too.
    var allowsPerpetual: Bool { self == .full }

    /// The precedence order itself, as a pure function so it can be asserted on directly.
    ///
    /// `reduceMotion` is checked first and returns immediately, which is what makes tier 1 a
    /// guarantee rather than a preference: no later tier is even consulted.
    static func resolve(reduceMotion: Bool, lowPower: Bool) -> MotionLevel {
        if reduceMotion { return .none }
        if lowPower { return .minimal }
        return .full
    }
}

extension EnvironmentValues {
    /// Read this rather than `accessibilityReduceMotion` directly, so the tier order above stays
    /// in one place.
    ///
    /// `isLowPowerModeEnabled` is sampled per view update rather than observed, so a mid-session
    /// toggle lands on the next redraw instead of instantly. Reduce Motion, the tier that
    /// actually matters, *is* a live environment value and updates immediately.
    var bqMotionLevel: MotionLevel {
        MotionLevel.resolve(
            reduceMotion: accessibilityReduceMotion,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}
