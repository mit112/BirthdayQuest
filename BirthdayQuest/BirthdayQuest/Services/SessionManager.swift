import Foundation
import SwiftUI
import Combine
import OSLog

// MARK: - App State

enum AppState: Equatable {
    case loading
    case characterSelect
    case birthdayBoyHome
    case friendHome
}

// MARK: - Session Manager

@MainActor
final class SessionManager: ObservableObject {
    
    static let shared = SessionManager()
    
    // MARK: - Published State
    
    @Published var appState: AppState = .loading
    @Published var currentUser: BQUser?
    @Published var gameState: GameState = .empty
    
    // Tab navigation — shared so any screen can switch tabs
    @Published var birthdayBoyTab: BirthdayBoyTab = .rewards
    @Published var friendTab: FriendTab = .secretChallenge
    
    // Navigation events — consumed by tab views
    @Published var scrollToLatestTimeline = false
    
    // MARK: - Persistence Keys
    
    private enum Keys {
        static let selectedCharacterId = "bq_selected_character_id"
        static let deviceId = "bq_device_id"
    }
    
    // MARK: - Computed Properties
    
    var selectedCharacterId: String? {
        UserDefaults.standard.string(forKey: Keys.selectedCharacterId)
    }
    
    var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: Keys.deviceId) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: Keys.deviceId)
        return newId
    }
    
    var isBirthdayBoy: Bool {
        currentUser?.role.isBirthdayBoy ?? false
    }
    
    var isFriend: Bool {
        currentUser?.role.isFriend ?? false
    }
    
    var isOrganizer: Bool {
        currentUser?.role.isOrganizer ?? false
    }
    
    var currentPoints: Int {
        gameState.currentPoints
    }
    
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "Session")
    private var listenersStarted = false

    // MARK: - Initialization

    private init() {}
    
    // MARK: - Bootstrap
    
    func bootstrap() async {
        // Ensure Firestore is seeded before anything else
        await DataSeeder.seedIfNeeded()
        
        // Check if user previously selected a character
        guard let characterId = selectedCharacterId else {
            appState = .characterSelect
            return
        }
        
        // Verify the character is still claimed by this device
        do {
            if let user = try await FirestoreService.shared.fetchUser(characterId: characterId),
               user.claimed && user.deviceId == deviceId {
                currentUser = user
                routeToHome(for: user.role)
                startListeners()
            } else {
                clearSession()
            }
        } catch {
            logger.error("Bootstrap error: \(error.localizedDescription)")
            clearSession()
        }
    }
    
    // MARK: - Character Selection
    
    func selectCharacter(_ user: BQUser) async throws {
        guard let characterId = user.id else { return }
        
        // Claim in Firestore
        try await FirestoreService.shared.claimCharacter(
            characterId: characterId,
            deviceId: deviceId
        )
        
        // Persist locally
        UserDefaults.standard.set(characterId, forKey: Keys.selectedCharacterId)
        
        // Update state
        var claimedUser = user
        claimedUser.claimed = true
        claimedUser.deviceId = deviceId
        currentUser = claimedUser
        
        routeToHome(for: user.role)
        startListeners()
    }
    
    // MARK: - Routing
    
    private func routeToHome(for role: UserRole) {
        withAnimation(BQDesign.Animation.smooth) {
            switch role {
            case .birthdayBoy:
                appState = .birthdayBoyHome
            case .friend, .organizer:
                appState = .friendHome
            }
        }
    }
    
    // MARK: - Real-time Listeners
    
    private func startListeners() {
        guard !listenersStarted else { return }
        listenersStarted = true

        // Game state — everyone needs this
        FirestoreService.shared.listenToGameState { [weak self] state in
            guard let state else { return }
            Task { @MainActor in
                self?.gameState = state
            }
        }
    }
    
    // MARK: - Session Management
    
    func clearSession() {
        UserDefaults.standard.removeObject(forKey: Keys.selectedCharacterId)
        currentUser = nil
        listenersStarted = false
        FirestoreService.shared.removeAllListeners()
        appState = .characterSelect
    }
    
    // MARK: - Tab Navigation
    
    /// The heartbeat — "Check out your timeline →"
    func navigateToTimeline() {
        BQDesign.Haptics.light()
        withAnimation(BQDesign.Animation.snappy) {
            if isBirthdayBoy {
                birthdayBoyTab = .timeline
            } else {
                friendTab = .timeline
            }
            // Signal timeline to scroll to latest
            scrollToLatestTimeline = true
        }
    }
}
