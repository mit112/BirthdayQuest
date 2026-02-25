import Foundation
import SwiftUI
import Combine

@MainActor
final class CharacterSelectViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var characters: [BQUser] = []
    @Published var selectedIndex: Int = 0
    @Published var isClaiming = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    // PIN bypass for locked characters
    @Published var showPinPrompt = false
    @Published var pinInput = ""
    @Published var showPinError = false
    
    private let overridePin = "0228" // Birthday date — friends won't guess randomly
    
    // MARK: - Computed
    
    var selectedCharacter: BQUser? {
        guard characters.indices.contains(selectedIndex) else { return nil }
        return characters[selectedIndex]
    }
    
    /// Button is always enabled (claimed characters route to PIN prompt)
    var canClaim: Bool {
        guard selectedCharacter != nil else { return false }
        return !isClaiming
    }
    
    /// Whether the selected character is already claimed by someone else
    var selectedIsClaimed: Bool {
        selectedCharacter?.claimed ?? false
    }
    
    // MARK: - Load Characters
    
    func startListening() {
        FirestoreService.shared.listenToUsers { [weak self] users in
            guard let self else { return }
            let sorted = users.sorted { a, b in
                if a.role == .birthdayBoy { return true }
                if b.role == .birthdayBoy { return false }
                return a.name < b.name
            }
            Task { @MainActor in
                self.characters = sorted
            }
        }
    }
    
    func stopListening() {
        FirestoreService.shared.removeListener(forKey: "users")
    }
    
    // MARK: - Claim Actions
    
    /// Called when "This is me" is tapped
    func handleClaimTap(session: SessionManager) async {
        guard let character = selectedCharacter else { return }
        
        if character.claimed {
            // Show PIN prompt
            pinInput = ""
            showPinError = false
            showPinPrompt = true
        } else {
            // Normal claim
            await claimCharacter(character, session: session)
        }
    }
    
    /// Called when PIN is submitted
    func submitPin(session: SessionManager) async {
        guard pinInput == overridePin else {
            showPinError = true
            BQDesign.Haptics.heavy()
            return
        }
        
        guard let character = selectedCharacter else { return }
        showPinPrompt = false
        await forceClaimCharacter(character, session: session)
    }
    
    // MARK: - Private
    
    private func claimCharacter(_ character: BQUser, session: SessionManager) async {
        isClaiming = true
        BQDesign.Haptics.medium()
        
        do {
            try await session.selectCharacter(character)
            BQDesign.Haptics.success()
        } catch {
            errorMessage = "Couldn't claim character. Try again!"
            showError = true
            BQDesign.Haptics.heavy()
        }
        
        isClaiming = false
    }
    
    /// Force-claim: overwrite existing claim
    private func forceClaimCharacter(_ character: BQUser, session: SessionManager) async {
        isClaiming = true
        BQDesign.Haptics.medium()
        
        do {
            // claimCharacter in FirestoreService just overwrites claimed + deviceId
            try await session.selectCharacter(character)
            BQDesign.Haptics.success()
        } catch {
            errorMessage = "Couldn't override character. Try again!"
            showError = true
            BQDesign.Haptics.heavy()
        }
        
        isClaiming = false
    }
}
