import SwiftUI
import FirebaseCore
import FirebaseFirestore
import AVFoundation

@main
struct BirthdayQuestApp: App {
    
    @StateObject private var session = AppSession()
    
    init() {
        FirebaseApp.configure()
        
        // Configure Firestore settings BEFORE any access
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
        
        // Configure audio session for reward playback
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        
        // Tab bar appearance (set once globally, not per-view)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundColor = UIColor(BQDesign.Colors.cardBackground)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                // The appearance is no longer pinned. Every `BQDesign` colour is now a
                // `UIColor(dynamicProvider:)` pair whose contrast is measured and pinned in
                // both schemes by `PaletteContrastTests`, and the page gradients and card
                // surfaces that used to hardcode light-only hexes are authored as brand tints
                // over surface tokens, so they follow the scheme too.
                //
                // The tab-bar appearance configured above needs no change for the same reason:
                // `UIColor(BQDesign.Colors.cardBackground)` now returns a dynamic colour, which
                // UIKit re-resolves per trait collection.
                //
                // Two things stay light-independent on purpose. The spy-dossier surfaces
                // (`secretDark`/`secretDeep`) are dark in BOTH appearances — their ~30 white
                // glyphs are correct as written, and flipping them would break all of them at
                // once; they earn separation from the page by lightness instead. And white text
                // on a saturated brand gradient is scheme-invariant, because the gradient is.
        }
    }
}
