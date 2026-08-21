import Foundation
import Combine
import OSLog

@MainActor
final class CreateOccasionViewModel: ObservableObject {

    @Published var name = ""
    @Published var celebrantName = ""
    @Published var occasionType: OccasionType = .birthday
    @Published var occasionDate = Date()
    @Published var hostName = ""
    @Published var hostAvatarId = AvatarCatalog.fallback

    @Published var isSubmitting = false
    @Published var errorMessage: String?

    private let service: GameBackend
    private let logger = Logger(subsystem: "com.example.birthdayquest", category: "CreateOccasion")

    init(service: GameBackend = FirestoreService.shared) {
        self.service = service
    }

    var canSubmit: Bool {
        !isSubmitting
            && !name.trimmed.isEmpty
            && !celebrantName.trimmed.isEmpty
            && !hostName.trimmed.isEmpty
    }

    /// Returns the new event id, or nil if creation failed.
    func create() async -> String? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            return try await service.createOccasion(
                name: name.trimmed,
                occasionType: occasionType,
                celebrantName: celebrantName.trimmed,
                occasionDate: occasionDate,
                hostName: hostName.trimmed,
                hostAvatarId: hostAvatarId
            )
        } catch {
            logger.error("Create occasion failed: \(error.localizedDescription)")
            errorMessage = "Couldn't create the occasion. Check your connection and try again."
            return nil
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
