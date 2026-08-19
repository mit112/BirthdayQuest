import Foundation
import SwiftUI
import PhotosUI
import FirebaseStorage
import Combine
import OSLog

@MainActor
final class ChallengeSubmissionViewModel: ObservableObject {
    
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "ChallengeSubmission")
    
    // MARK: - Published
    
    @Published var challenge: Challenge
    @Published var selectedSubmissionType: SubmissionType = .photo
    @Published var textProof: String = ""
    @Published var selectedPhoto: PhotosPickerItem?
    @Published var selectedImageData: Data?
    @Published var previewImage: UIImage?

    @Published var isSubmitting = false
    @Published var submitSuccess = false
    @Published var showTimelinePrompt = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    // MARK: - Init
    
    private let service: GameBackend

    init(challenge: Challenge, service: GameBackend = FirestoreService.shared) {
        self.service = service
        self.challenge = challenge
    }
    
    // MARK: - Computed
    
    var canSubmit: Bool {
        guard !isSubmitting, !challenge.isCompleted else { return false }
        switch selectedSubmissionType {
        case .photo:
            return selectedImageData != nil
        case .text:
            return !textProof.trimmingCharacters(in: .whitespaces).isEmpty
        case .button:
            return true
        }
    }
    
    // MARK: - Photo Selection
    
    func handlePhotoSelection() async {
        guard let item = selectedPhoto else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                selectedImageData = data
                previewImage = UIImage(data: data)
            }
        } catch {
            logger.error("Photo load error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Submit
    
    func submit() async {
        guard canSubmit, let challengeId = challenge.id else { return }
        
        isSubmitting = true
        BQDesign.Haptics.medium()
        
        do {
            var proofUrl: String?
            var proofType: String?
            var proofText: String?
            
            switch selectedSubmissionType {
            case .photo:
                if let data = selectedImageData {
                    let compressed = compressImage(data)
                    proofUrl = try await uploadProof(data: compressed, ext: "jpg", challengeId: challengeId)
                    proofType = "photo"
                }
            case .text:
                proofText = textProof.trimmingCharacters(in: .whitespaces)
                proofType = "text"
            case .button:
                proofType = "button"
            }
            
            // Single atomic batch: complete + points + timeline (+ secret counter if needed)
            let event = TimelineEvent(
                type: .challengeCompleted,
                referenceId: challengeId,
                title: "Completed: \(challenge.title)",
                subtitle: "+\(challenge.pointValue) ✦",
                badgeType: .challenge,
                badgeAsset: challenge.illustrationAsset,
                fromFriendName: nil,
                fromFriendAvatar: nil,
                timestamp: Date()
            )
            
            try await service.completeChallengeAtomically(
                challengeId: challengeId,
                pointValue: challenge.pointValue,
                isSecret: challenge.isSecret,
                proofUrl: proofUrl,
                proofType: proofType,
                proofText: proofText,
                timelineEvent: event
            )
            
            // Success!
            submitSuccess = true
            BQDesign.Haptics.success()
            
            try? await Task.sleep(for: .milliseconds(1200))
            showTimelinePrompt = true
            
        } catch {
            errorMessage = "Submission failed. Try again!"
            showError = true
            BQDesign.Haptics.heavy()
        }
        
        isSubmitting = false
    }
    
    // MARK: - Upload Helper
    
    private func uploadProof(data: Data, ext: String, challengeId: String) async throws -> String {
        let filename = "\(UUID().uuidString).\(ext)"
        let path = "proofs/\(challengeId)/\(filename)"
        return try await service.uploadProofData(data, path: path)
    }
    
    // MARK: - Image Compression (#8)
    
    /// Compresses image data to ~500KB JPEG. Prevents 5MB+ raw photos from killing cellular uploads.
    private func compressImage(_ data: Data, maxKB: Int = 500) -> Data {
        guard let image = UIImage(data: data) else { return data }
        var quality: CGFloat = 0.8
        var compressed = image.jpegData(compressionQuality: quality)
        while let c = compressed, c.count > maxKB * 1024, quality > 0.15 {
            quality -= 0.1
            compressed = image.jpegData(compressionQuality: quality)
        }
        return compressed ?? data
    }

}
