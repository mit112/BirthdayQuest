import Foundation

/// The symbols a host may attach to a challenge.
///
/// `Challenge.illustrationAsset` is interpreted as an SF Symbol name and falls back to
/// `bolt.fill` when it is not one (`TimelineNodeView.badgeIcon`). The dare flow writes the
/// literal `"secret_mission"`, which is not a symbol, so every secret dare has always
/// rendered the fallback and nobody noticed — a silent fallback is invisible by
/// construction. A curated list is what stops an authoring form reproducing that on purpose.
///
/// Mirrors `AvatarCatalog`: a fixed set, a fallback, and a test asserting every entry
/// actually resolves.
enum ChallengeSymbolCatalog {

    static let all: [String] = [
        "music.mic", "figure.run", "camera.fill", "paintbrush.fill",
        "heart.fill", "star.fill", "gift.fill", "book.fill",
        "fork.knife", "map.fill", "phone.fill", "hand.wave.fill",
        "theatermasks.fill", "bicycle", "leaf.fill", "sparkles",
        "flame.fill", "bolt.fill",
    ]

    static let fallback = "sparkles"

    static func resolved(_ name: String) -> String {
        all.contains(name) ? name : fallback
    }
}
