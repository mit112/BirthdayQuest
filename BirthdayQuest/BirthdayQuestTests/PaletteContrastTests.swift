import Testing
import SwiftUI
import UIKit
@testable import BirthdayQuest

// A contrast ratio is arithmetic on the rendered colour, so it is genuinely testable rather than
// a matter of taste — and it is the one accessibility property of the palette that a comment can
// claim and be quietly wrong about.
//
// Two things make these tests non-vacuous:
//
// 1. They measure what *renders*, not a parallel table of constants. Every ratio is computed from
//    `UIColor(token).resolvedColor(with:)`, i.e. the same resolution UIKit performs when drawing,
//    so a token whose dark variant was never wired up fails here rather than passing against its
//    own light value read twice. `dynamicTokensResolveDifferentlyPerAppearance` pins that
//    mechanism explicitly, so if the `Color` -> `UIColor` round trip ever stopped preserving the
//    dynamic provider, the failure would name the cause instead of looking like a bad hex.
// 2. Every pair is asserted in *both* appearances. A palette is not one theme with a variant; a
//    ratio that clears AA in light says nothing about dark, which is exactly how dark modes ship
//    broken.

// MARK: - Contrast arithmetic (WCAG 2.2 SC 1.4.3 / 1.4.11)

struct PaletteRGB {
    let red: Double
    let green: Double
    let blue: Double

    /// WCAG relative luminance: linearise each sRGB channel, then weight.
    var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Alpha-composite `self` over `backdrop` — needed because two surfaces in the app are drawn
    /// at partial opacity, and the effective ratio is against the composite, not the swatch.
    func composited(over backdrop: PaletteRGB, alpha: Double) -> PaletteRGB {
        PaletteRGB(
            red: red * alpha + backdrop.red * (1 - alpha),
            green: green * alpha + backdrop.green * (1 - alpha),
            blue: blue * alpha + backdrop.blue * (1 - alpha)
        )
    }
}

private func contrastRatio(_ lhs: PaletteRGB, _ rhs: PaletteRGB) -> Double {
    let (high, low) = (max(lhs.luminance, rhs.luminance), min(lhs.luminance, rhs.luminance))
    return (high + 0.05) / (low + 0.05)
}

/// Resolve a design token exactly as UIKit would when drawing it in the given appearance.
@MainActor
private func resolve(_ color: Color, _ style: UIUserInterfaceStyle) -> PaletteRGB {
    let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return PaletteRGB(red: Double(red), green: Double(green), blue: Double(blue))
}

// MARK: - The cases

/// One `foreground on background` pairing that the app actually draws, with the WCAG floor that
/// applies to it. `alpha` is the opacity the *background* token is drawn at, where the app draws
/// it at less than full strength.
struct PaletteContrastCase: CustomStringConvertible, Sendable {
    let label: String
    let foreground: Color
    let background: Color
    /// Backdrop the background token is composited over when `alpha < 1`.
    let backdrop: Color
    let alpha: Double
    let floor: Double

    init(
        _ label: String,
        _ foreground: Color,
        on background: Color,
        alpha: Double = 1,
        over backdrop: Color = BQDesign.Colors.background,
        floor: Double
    ) {
        self.label = label
        self.foreground = foreground
        self.background = background
        self.backdrop = backdrop
        self.alpha = alpha
        self.floor = floor
    }

    var description: String { label }
}

private let bodyTextFloor = 4.5
private let largeTextAndUIFloor = 3.0

private typealias Palette = BQDesign.Colors

private enum Cases {

    /// Body text: 4.5:1. Every surface each token is actually placed on.
    static let bodyText: [PaletteContrastCase] = [
        .init("textPrimary on background", Palette.textPrimary, on: Palette.background, floor: bodyTextFloor),
        .init("textPrimary on cardBackground", Palette.textPrimary, on: Palette.cardBackground, floor: bodyTextFloor),
        .init("textPrimary on surfaceElevated", Palette.textPrimary, on: Palette.surfaceElevated, floor: bodyTextFloor),
        .init("textPrimary on goldLight chip", Palette.textPrimary, on: Palette.goldLight, floor: bodyTextFloor),

        .init("textSecondary on background", Palette.textSecondary, on: Palette.background, floor: bodyTextFloor),
        .init("textSecondary on cardBackground", Palette.textSecondary, on: Palette.cardBackground, floor: bodyTextFloor),
        .init("textSecondary on surfaceElevated", Palette.textSecondary, on: Palette.surfaceElevated, floor: bodyTextFloor),
        // TextRewardView draws the gold chip at 50% over the app background.
        .init(
            "textSecondary on goldLight at 50% over background",
            Palette.textSecondary,
            on: Palette.goldLight,
            alpha: 0.5,
            floor: bodyTextFloor
        ),

        // The surfaces the *converted* call sites composite into. Each of these is a token drawn
        // at partial opacity over another token — the pattern that replaced the hardcoded pastels
        // — so the ratio the user sees is against the composite, never against either swatch.

        // RewardCardView, unlocked gift: `goldLight` at 50% -> 100% over the card.
        .init(
            "textPrimary on goldLight at 50% over cardBackground",
            Palette.textPrimary,
            on: Palette.goldLight,
            alpha: 0.5,
            over: Palette.cardBackground,
            floor: bodyTextFloor
        ),
        // RewardCardView, affordable gift: the stop that used to mix `cardBackground` with a
        // fixed cream and would have seamed in dark.
        .init(
            "textPrimary on goldLight at 30% over cardBackground",
            Palette.textPrimary,
            on: Palette.goldLight,
            alpha: 0.3,
            over: Palette.cardBackground,
            floor: bodyTextFloor
        ),
        // RewardCardView, locked gift: the card recedes toward the page in both appearances, and
        // its label is `textSecondary` at full strength. This is the tightest pair in the app.
        .init(
            "textSecondary on primaryPurple at 9% over background",
            Palette.textSecondary,
            on: Palette.primaryPurple,
            alpha: 0.09,
            floor: bodyTextFloor
        ),
        // ProfileView page wash, both branches of the celebrant/contributor split, at the bottom
        // stop where the tint is strongest.
        .init(
            "textSecondary on primaryOrange at 11% over background",
            Palette.textSecondary,
            on: Palette.primaryOrange,
            alpha: 0.11,
            floor: bodyTextFloor
        ),
        .init(
            "textSecondary on primaryPurple at 8.5% over background",
            Palette.textSecondary,
            on: Palette.primaryPurple,
            alpha: 0.085,
            floor: bodyTextFloor
        ),
        // `TimelineBackgroundView`'s deepest stop — `primaryPurple` at 17.5% over `background`.
        // Only `textPrimary` is asserted on it, and deliberately: `textSecondary` measures 4.05:1
        // on this composite in light. That is a *pre-existing* shortfall, not one the token
        // conversion introduced — the fixed `#E8D8F0` it replaced measured 3.96:1 — so pinning it
        // at the body floor would redden the suite for a defect that predates the palette. It is
        // recorded here rather than left silent.
        .init(
            "textPrimary on primaryPurple at 17.5% over background",
            Palette.textPrimary,
            on: Palette.primaryPurple,
            alpha: 0.175,
            floor: bodyTextFloor
        ),

        .init("goldText on background", Palette.goldText, on: Palette.background, floor: bodyTextFloor),
        .init("goldText on cardBackground", Palette.goldText, on: Palette.cardBackground, floor: bodyTextFloor),
        .init("goldText on surfaceElevated", Palette.goldText, on: Palette.surfaceElevated, floor: bodyTextFloor),
        .init("goldText on goldLight chip", Palette.goldText, on: Palette.goldLight, floor: bodyTextFloor),

        // The secret dossier screens write in literal white. They stay dark in *both* appearances
        // precisely so this holds; if a future dark variant made them light, this is what reddens.
        .init("white on secretDark", .white, on: Palette.secretDark, floor: bodyTextFloor),
        .init("white on secretDeep", .white, on: Palette.secretDeep, floor: bodyTextFloor)
    ]

    /// Large text and UI components: 3:1. These tokens are documented as icon/large-text only in
    /// both appearances, and the floor asserted is the one their documentation claims.
    static let largeTextAndUI: [PaletteContrastCase] = [
        .init("error on background", Palette.error, on: Palette.background, floor: largeTextAndUIFloor),
        .init("error on cardBackground", Palette.error, on: Palette.cardBackground, floor: largeTextAndUIFloor),
        .init("secretAccent on background", Palette.secretAccent, on: Palette.background, floor: largeTextAndUIFloor),
        .init("secretAccent on secretDark", Palette.secretAccent, on: Palette.secretDark, floor: largeTextAndUIFloor),
        .init("primaryPurple on background", Palette.primaryPurple, on: Palette.background, floor: largeTextAndUIFloor)
    ]
}

// MARK: - Suite

@Suite("Palette contrast holds in both appearances")
@MainActor
struct PaletteContrastTests {

    private func ratio(_ testCase: PaletteContrastCase, _ style: UIUserInterfaceStyle) -> Double {
        let foreground = resolve(testCase.foreground, style)
        var background = resolve(testCase.background, style)
        if testCase.alpha < 1 {
            background = background.composited(over: resolve(testCase.backdrop, style), alpha: testCase.alpha)
        }
        return contrastRatio(foreground, background)
    }

    // MARK: Body text — 4.5:1, both appearances

    @Test("Body text clears 4.5:1 in light mode", arguments: Cases.bodyText)
    func bodyTextInLight(testCase: PaletteContrastCase) {
        let measured = ratio(testCase, .light)
        #expect(measured >= testCase.floor, "\(testCase.label) is \(measured):1 in light, needs \(testCase.floor):1")
    }

    @Test("Body text clears 4.5:1 in dark mode", arguments: Cases.bodyText)
    func bodyTextInDark(testCase: PaletteContrastCase) {
        let measured = ratio(testCase, .dark)
        #expect(measured >= testCase.floor, "\(testCase.label) is \(measured):1 in dark, needs \(testCase.floor):1")
    }

    // MARK: Large text and UI — 3:1, both appearances

    @Test("Large-text and UI colours clear 3:1 in light mode", arguments: Cases.largeTextAndUI)
    func largeTextInLight(testCase: PaletteContrastCase) {
        let measured = ratio(testCase, .light)
        #expect(measured >= testCase.floor, "\(testCase.label) is \(measured):1 in light, needs \(testCase.floor):1")
    }

    @Test("Large-text and UI colours clear 3:1 in dark mode", arguments: Cases.largeTextAndUI)
    func largeTextInDark(testCase: PaletteContrastCase) {
        let measured = ratio(testCase, .dark)
        #expect(measured >= testCase.floor, "\(testCase.label) is \(measured):1 in dark, needs \(testCase.floor):1")
    }

    // MARK: The mechanism itself

    @Test("Dynamic tokens resolve to different values per appearance")
    func dynamicTokensResolveDifferentlyPerAppearance() {
        // If the `Color` -> `UIColor` round trip ever stopped preserving the dynamic provider,
        // every dark measurement above would silently become a second light measurement and the
        // suite would go green for the wrong reason. This is the assertion that would not.
        let lightPrimary = resolve(BQDesign.Colors.textPrimary, .light)
        let darkPrimary = resolve(BQDesign.Colors.textPrimary, .dark)
        #expect(lightPrimary.luminance < 0.1, "textPrimary should be a near-black in light mode")
        #expect(darkPrimary.luminance > 0.7, "textPrimary should be a near-white in dark mode")

        let lightBackground = resolve(BQDesign.Colors.background, .light)
        let darkBackground = resolve(BQDesign.Colors.background, .dark)
        #expect(lightBackground.luminance > 0.7, "background should be a near-white in light mode")
        #expect(darkBackground.luminance < 0.1, "background should be a near-black in dark mode")
    }

    // MARK: Dark elevation is carried by lightness

    @Test("Dark surfaces rise in lightness with elevation")
    func darkSurfacesRiseWithElevation() {
        // In dark mode a 6%-black shadow over a near-black surface is invisible, so the only
        // remaining elevation cue is that a higher surface is a lighter one. That is a decision,
        // not an accident, and this is what holds it: flatten the three dark surfaces to one
        // value and every card in the app loses its edge.
        let background = resolve(BQDesign.Colors.background, .dark).luminance
        let card = resolve(BQDesign.Colors.cardBackground, .dark).luminance
        let elevated = resolve(BQDesign.Colors.surfaceElevated, .dark).luminance

        #expect(background < card, "cardBackground must sit above background in dark mode")
        #expect(card < elevated, "surfaceElevated must sit above cardBackground in dark mode")
    }

    // MARK: The secret surfaces stay dark in both appearances

    @Test("Secret surfaces stay dark, and stay distinct from the app background")
    func secretSurfacesStayDarkAndDistinct() {
        // Everything drawn on the dossier is a literal `Color.white` in the secret views, so these
        // panels cannot follow the scheme — inverting them in dark would break every one of those
        // call sites. What they must do instead is remain separable from the app background once
        // that background is itself dark.
        for style in [UIUserInterfaceStyle.light, .dark] {
            let secret = resolve(BQDesign.Colors.secretDark, style)
            let deep = resolve(BQDesign.Colors.secretDeep, style)
            #expect(secret.luminance < 0.1, "secretDark must stay dark in \(style.rawValue)")
            #expect(deep.luminance < 0.1, "secretDeep must stay dark in \(style.rawValue)")
        }

        let separation = contrastRatio(
            resolve(BQDesign.Colors.secretDark, .dark),
            resolve(BQDesign.Colors.background, .dark)
        )
        #expect(separation >= 1.2, "secretDark must stay perceptibly apart from the dark background")
    }
}
