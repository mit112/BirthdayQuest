import SwiftUI

// MARK: - BirthdayQuest Design System
// "Headspace meets Duolingo" — warm, playful, layered, alive.

enum BQDesign {
    
    // MARK: - Color Palette

    /// Every token carries an explicit value in *each* appearance, and every text-capable one
    /// records its measured contrast ratio in both.
    ///
    /// **Mechanism.** A token is a `Color` wrapping a `UIColor(dynamicProvider:)`. UIKit
    /// re-resolves that against the trait collection of whatever is drawing it, so one `Color` is
    /// correct in both schemes with nothing threaded through call sites — no
    /// `@Environment(\.colorScheme)` for a view to forget to read, and no second code path to
    /// keep in sync. It resolves at *draw* time, which is why the `static let` gradients below
    /// adapt too, even though each is built exactly once. An asset-catalog Color Set resolves by
    /// the identical mechanism, but it would move the values out of the one file that records
    /// what they measure, and would not save a single call-site edit.
    ///
    /// **Which surface a ratio is against.** The binding surface flips with the scheme. In light
    /// the tokens are darker than their surface, so the *darkest* surface — `background`
    /// `#FBF7F4` — yields the smallest ratio. In dark they are lighter than their surface, so the
    /// *lightest* one — `surfaceElevated` `#2C2939` — does. Each comment quotes `light / dark`
    /// against that binding case; anywhere else in the same scheme the token measures higher.
    /// WCAG 2.2 AA needs 4.5:1 for body text and 3:1 for large text and UI.
    ///
    /// **Dark is authored, not derived.** No dark value is an inversion of its light one: hue is
    /// held, chroma lowered and lightness raised, so nothing blooms on an OLED panel. No dark
    /// surface is `#000`; each is a near-black tinted toward the palette's violet, and they rise
    /// in lightness with elevation, because on a dark surface it is lightness — not a shadow —
    /// that reads as height.
    enum Colors {

        // MARK: Primary — the signature gradient
        //
        // Fills, glyphs and gradient stops; never a sentence. `primaryPink` and `primaryOrange`
        // are under 3:1 in light and so are not even UI-boundary colours there.
        static let primaryPurple = adaptive(light: 0x7C_5C_FC, dark: 0xA7_97_F5) // 4.11:1 / 5.65:1
        static let primaryPink = adaptive(light: 0xFF_6B_9D, dark: 0xF5_90_B0) // 2.51:1 / 6.40:1
        static let primaryOrange = adaptive(light: 0xFF_A4_5B, dark: 0xF5_B9_84) // 1.84:1 / 8.19:1

        // MARK: Surfaces
        //
        // Light keeps both of its original values untouched: a warm off-white app background with
        // pure-white cards riding on it, where a 1.07:1 step plus a shadow reads as elevation.
        // Dark cannot borrow that trick — a 6%-black shadow over a near-black surface is
        // invisible — so the dark surfaces separate by lightness instead: 1.16:1 from `background`
        // to `cardBackground`, a further 1.12:1 up to `surfaceElevated`.
        static let background = adaptive(light: 0xFB_F7_F4, dark: 0x15_13_1C)
        static let cardBackground = adaptive(light: 0xFF_FF_FF, dark: 0x23_20_30)
        static let surfaceElevated = adaptive(light: 0xFF_FF_FF, dark: 0x2C_29_39)

        // MARK: Text hierarchy

        static let textPrimary = adaptive(light: 0x2D_2B_3D, dark: 0xF2_EF_F7) // 12.93:1 / 12.45:1 — any size
        static let textSecondary = adaptive(light: 0x6B_68_80, dark: 0x9C_97_AD) // 5.03:1 / 5.02:1 — any size

        /// **Not a text colour, in either scheme.** Its job is to be barely there — divider rules,
        /// skeleton fills, page dots, progress tracks — and it is measured against `background`,
        /// which is what decoration sits on: 1.88:1 in light, 1.87:1 in dark. That near-identical
        /// pair is the point; the role is the same faintness both ways, which is why the dark
        /// value is a dim *lighter* mark on a dark surface rather than a lightened mirror of the
        /// light one. It fails AA for body *and* large text in both schemes, so anything a user
        /// has to read takes `textSecondary`, the lightest token that clears AA. Kept low on
        /// purpose: that is exactly what makes it right for a 15%-opacity skeleton block and
        /// wrong for a sentence. (On a card it is fainter still — 2.01:1 light, 1.44:1 dark.)
        static let textTertiary = adaptive(light: 0xB8_B5_C6, dark: 0x45_41_54)

        // MARK: Accents
        //
        // `gold`, `success` and `challengeBlue` are fills, glyphs and badges — not text. In dark
        // they measure 7.65:1, 7.28:1 and 6.64:1 and *would* carry a sentence, but light is the
        // binding scheme at 1.90:1, 1.73:1 and 2.61:1, and the rule stays one rule in both: the
        // sentence beside them is `textPrimary` or `goldText`.
        static let gold = adaptive(light: 0xF5_A6_23, dark: 0xF0_B4_4E) // 1.90:1 / 7.65:1 — never text

        /// `gold` for text. Same hue family as `gold`, moved in lightness until it clears AA body
        /// text on the surface of the day — *down* in light (4.65:1 on `background`, 4.95:1 on a
        /// card) and *up* in dark (8.64:1 on `surfaceElevated`, 11.22:1 on `background`). Use it
        /// for point values and earned totals; keep `gold` for the fills, glyphs and badges beside
        /// them, so the accent survives while the number stays readable.
        static let goldText = adaptive(light: 0x9C_64_07, dark: 0xF0_C4_6A)

        /// The lighter stop of `goldGradient`. A gradient stop, never text — 1.44:1 in light.
        static let goldHighlight = adaptive(light: 0xFF_C8_57, dark: 0xFF_D9_8A)

        /// The gold *chip*: the capsule behind a points total, and at 50% opacity the letter-gift
        /// card. It is a surface, so what matters is what sits on it. `textPrimary` on the
        /// full-strength chip reads 12.53:1 light / 11.68:1 dark. `textSecondary` on the
        /// 50%-over-`background` composite reads 4.95:1 light / 5.68:1 dark. `goldText` on the
        /// full chip reads 4.51:1 light / 8.10:1 dark — clearing AA body text both ways, but by
        /// 0.01 in light, so do not darken the chip or lighten `goldText` without re-measuring.
        static let goldLight = adaptive(light: 0xFF_F3_DC, dark: 0x3A_2E_14)

        static let success = adaptive(light: 0x4C_D9_64, dark: 0x57_D1_77) // 1.73:1 / 7.28:1 — never text
        static let challengeBlue = adaptive(light: 0x5B_9F_E6, dark: 0x7F_B6_F0) // 2.61:1 / 6.64:1 — never text

        // MARK: The secret ("dossier") surfaces
        //
        // The one place the palette deliberately does not follow the scheme. These are full-bleed
        // identity surfaces and everything written on them is a literal `Color.white` in the
        // secret views, so they must stay dark in *both* appearances — turning them light in dark
        // mode would break every one of those call sites at once, and none of them is a token
        // this file can fix. What does change is how they earn their separation: in light they
        // are the dark thing on a light app (16.01:1 against `background`), and in dark that
        // disappears (1.24:1). So the dark values are nudged *up* in lightness and saturation —
        // the same "a higher surface is a lighter surface" cue the app's own cards now use — which
        // leaves a real 1.24:1 step, on the order of the 1.16:1 card step, instead of the panel
        // dissolving into the background.
        //
        // On these panels: `Color.white` 17.06:1 / 14.85:1 on `secretDark` and 15.89:1 / 13.37:1
        // on `secretDeep`; `gold` 8.42:1 / 8.02:1; `success` 9.27:1 / 7.63:1.
        //
        // One consequence worth naming, because it has been a standing hazard: `textSecondary` on
        // `secretDark` measures 3.18:1 in light — under AA — and 5.26:1 in dark. Dark fixed it;
        // light did not. No view puts it there today and none may start.
        static let secretDark = adaptive(light: 0x1A_1A_2E, dark: 0x26_23_47)

        /// The deeper stop of `secretGradient`.
        static let secretDeep = adaptive(light: 0x16_21_3E, dark: 0x1F_2E_52)

        /// The crimson accent on the dossier, and the destructive tint on the host controls.
        /// 4.46:1 light / 5.82:1 dark on `secretDark`; on the ordinary app surfaces it measures
        /// 3.59:1 / 5.54:1 and so — exactly like `error`, whose value it shares — it is large-text
        /// and UI only.
        static let secretAccent = adaptive(light: 0xE9_45_60, dark: 0xF1_80_8F)

        // MARK: Semantic
        //
        // 3.59:1 / 5.54:1. Light is the binding scheme and it is under 4.5:1, so this stays
        // large-text-and-UI only in both. The error rows across the occasion, create, join and
        // host-panel surfaces put this on the *icon* and leave the sentence at `textPrimary`;
        // copy that split rather than tinting the text.
        static let error = adaptive(light: 0xE9_45_60, dark: 0xF1_80_8F)

        /// The same token as `gold`, named for where it is spent. Aliased rather than repeated so
        /// the two cannot drift apart in one appearance and not the other.
        static let pointsGold = gold

        // MARK: Gradients
        //
        // Built from the tokens above, so they adapt for free: a `Color` resolves at draw time,
        // not when the `static let` holding it is initialised.

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
            colors: [gold, goldHighlight],
            startPoint: .top,
            endPoint: .bottom
        )

        static let secretGradient = LinearGradient(
            colors: [secretDark, secretDeep],
            startPoint: .top,
            endPoint: .bottom
        )

        // MARK: Category tint

        /// The two-stop tint a challenge category is drawn with — the single source of truth for
        /// both the card (`ChallengeCardView`) and the detail header (`ChallengeDetailView`).
        ///
        /// It was two copies with identical values and nothing keeping them identical; an
        /// invariant audit found the second one, unrecorded. The values here are unchanged from
        /// both, so unifying them is a pure de-duplication.
        ///
        /// Deliberately still MIXED — three cases are fixed hexes, two are adaptive brand tokens
        /// — and that inconsistency, rather than the fixed hexes on their own, is the open defect:
        /// inside one array the brand stop shifts between light and dark while the hex beside it
        /// does not, so the gradient's two ends drift apart in dark mode. Which way to resolve it
        /// is a real design call and is **not** settled here. A saturated brand gradient carrying
        /// white glyphs is legitimately scheme-invariant under this file's own doctrine, so making
        /// all ten stops fixed is as defensible as making all ten adaptive — and either way the
        /// result has to be checked by eye in both appearances, which is why this commit does not
        /// guess at eight dark values it cannot verify.
        static func categoryTint(_ category: ChallengeCategory) -> [Color] {
            switch category {
            case .physical: return [Color(hex: "4CAF50"), Color(hex: "66BB6A")]
            case .social: return [Color(hex: "5B9FE6"), Color(hex: "7BB3ED")]
            case .creative: return [primaryPurple, primaryPink]
            case .sentimental: return [primaryPink, Color(hex: "FF8FB1")]
            case .adventure: return [primaryOrange, Color(hex: "FFB74D")]
            }
        }

        // MARK: Appearance resolution

        /// A token with an explicit, hand-picked value in each appearance.
        ///
        /// The pair is `0xRRGGBB` rather than a string so a typo is a compile error rather than a
        /// silent black (`Color(hex:)` falls back to black on a malformed string), and so the
        /// tests can compare against the same literal form the designer reads.
        private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(uiColor: UIColor { traits in
                srgb(traits.userInterfaceStyle == .dark ? dark : light)
            })
        }

        private static func srgb(_ rgb: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        }
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
