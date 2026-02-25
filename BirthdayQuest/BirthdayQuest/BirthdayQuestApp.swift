import SwiftUI
import FirebaseCore
import FirebaseFirestore
import AVFoundation

@main
struct BirthdayQuestApp: App {
    
    @StateObject private var session = SessionManager.shared
    
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
        }
    }
}
