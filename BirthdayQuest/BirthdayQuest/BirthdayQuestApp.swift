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
                // Every BQDesign colour is a fixed hex with no dark variant, and the tab bar
                // above is pinned to a light `cardBackground`. Surfaces that lean on a
                // system-adaptive background instead — the plain `List` in `OccasionListView`,
                // for one — would put near-black `textPrimary` on dark grey in dark mode, which
                // measures about 1.1:1. Pin the appearance the palette was actually designed for
                // rather than shipping unreadable text; a real dark theme means dark variants for
                // every token, which is its own piece of work.
                .preferredColorScheme(.light)
        }
    }
}
