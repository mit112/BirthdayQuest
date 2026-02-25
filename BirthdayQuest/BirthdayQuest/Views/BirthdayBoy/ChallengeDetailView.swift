import SwiftUI
import PhotosUI
import ConfettiSwiftUI

struct ChallengeDetailView: View {
    
    let challenge: Challenge
    let onDismiss: () -> Void
    
    @EnvironmentObject private var session: SessionManager
    @StateObject private var viewModel: ChallengeSubmissionViewModel
    @State private var confettiTrigger = 0
    
    init(challenge: Challenge, onDismiss: @escaping () -> Void) {
        self.challenge = challenge
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: ChallengeSubmissionViewModel(challenge: challenge))
    }
    
    var body: some View {
        ZStack {
            BQDesign.Colors.background.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: BQDesign.Spacing.lg) {
                    // Drag handle
                    Capsule()
                        .fill(BQDesign.Colors.textTertiary.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, BQDesign.Spacing.md)
                    
                    // Hero illustration
                    challengeHero
                    
                    // Info section
                    infoSection
                    
                    // Submission area
                    if !challenge.isCompleted {
                        submissionSection
                    } else {
                        completedBanner
                    }
                    
                    // Timeline prompt
                    if viewModel.showTimelinePrompt {
                        timelineButton
                    }
                    
                    Spacer().frame(height: BQDesign.Spacing.xxl)
                }
                .padding(.horizontal, BQDesign.Spacing.lg)
            }
            
            // Confetti overlay
            Color.clear
                .confettiCannon(
                    trigger: $confettiTrigger,
                    num: 60,
                    colors: [
                        Color(hex: "7C5CFC"),
                        Color(hex: "FF6B9D"),
                        Color(hex: "FFA45B"),
                        Color(hex: "F5A623")
                    ],
                    rainHeight: 500,
                    radius: 350
                )
                .allowsHitTesting(false)
        }
        .onChange(of: viewModel.submitSuccess) { _, success in
            if success { confettiTrigger += 1 }
        }
        .onChange(of: viewModel.selectedPhoto) { _, _ in
            Task {
                if challenge.submissionType == .video {
                    await viewModel.handleVideoSelection()
                } else {
                    await viewModel.handlePhotoSelection()
                }
            }
        }
        .alert("Oops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong")
        }
    }
}

// MARK: - Subviews

private extension ChallengeDetailView {
    
    // MARK: Hero
    var challengeHero: some View {
        ZStack {
            Circle()
                .fill(categoryGradient)
                .frame(width: 100, height: 100)
            
            Image(systemName: challenge.category.icon)
                .font(.system(size: 40))
                .foregroundColor(.white)
        }
        .bqShadow(BQDesign.Shadows.glow)
        .padding(.top, BQDesign.Spacing.md)
    }
    
    // MARK: Info
    var infoSection: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            Text(challenge.title)
                .font(BQDesign.Typography.screenTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text(challenge.description)
                .font(BQDesign.Typography.body)
                .foregroundColor(BQDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            // Metadata row — equal-width columns
            HStack(spacing: 0) {
                // Points
                VStack(spacing: 4) {
                    Text("✦ \(challenge.pointValue)")
                        .font(BQDesign.Typography.points)
                        .foregroundColor(BQDesign.Colors.gold)
                    Text("Points")
                        .font(BQDesign.Typography.captionSmall)
                        .foregroundColor(BQDesign.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                
                // Divider
                Rectangle()
                    .fill(BQDesign.Colors.textTertiary.opacity(0.15))
                    .frame(width: 1, height: 32)
                
                // Difficulty
                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        ForEach(0..<challenge.difficulty.stars, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                        }
                    }
                    .foregroundColor(Color(hex: challenge.difficulty.color))
                    Text("Difficulty")
                        .font(BQDesign.Typography.captionSmall)
                        .foregroundColor(BQDesign.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                
                // Divider
                Rectangle()
                    .fill(BQDesign.Colors.textTertiary.opacity(0.15))
                    .frame(width: 1, height: 32)
                
                // Type
                VStack(spacing: 4) {
                    Image(systemName: challenge.submissionType.icon)
                        .font(.system(size: 18))
                        .foregroundColor(BQDesign.Colors.primaryPurple)
                    Text(challenge.submissionType.label)
                        .font(BQDesign.Typography.captionSmall)
                        .foregroundColor(BQDesign.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, BQDesign.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                    .fill(BQDesign.Colors.cardBackground)
            )
            .bqShadow(BQDesign.Shadows.card)
        }
    }
    
    // MARK: Submission Section
    @ViewBuilder
    var submissionSection: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Text("Submit Proof")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
            
            switch challenge.submissionType {
            case .photo:
                photoSubmission
            case .video:
                videoSubmission
            case .text:
                textSubmission
            case .button:
                buttonSubmission
            }
        }
    }
    
    // MARK: Photo Submission
    var photoSubmission: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            if let image = viewModel.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous))
                    .bqShadow(BQDesign.Shadows.card)
            }
            
            PhotosPicker(
                selection: $viewModel.selectedPhoto,
                matching: .images
            ) {
                HStack(spacing: BQDesign.Spacing.sm) {
                    Image(systemName: viewModel.previewImage != nil ? "arrow.triangle.2.circlepath" : challenge.submissionType.icon)
                        .font(.system(size: 16))
                    Text(viewModel.previewImage != nil ? "Choose Different" : "Select \(challenge.submissionType.label)")
                        .font(BQDesign.Typography.bodyBold)
                }
                .foregroundColor(BQDesign.Colors.primaryPurple)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                        .stroke(BQDesign.Colors.primaryPurple, lineWidth: 1.5)
                )
            }
            
            submitButton
        }
    }
    
    // MARK: Video Submission
    var videoSubmission: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            if viewModel.selectedVideoData != nil {
                HStack(spacing: BQDesign.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(BQDesign.Colors.success)
                    Text("Video selected")
                        .font(BQDesign.Typography.body)
                        .foregroundColor(BQDesign.Colors.textPrimary)
                }
                .padding(BQDesign.Spacing.md)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                        .fill(BQDesign.Colors.success.opacity(0.1))
                )
            }
            
            PhotosPicker(
                selection: $viewModel.selectedPhoto,
                matching: .videos
            ) {
                HStack(spacing: BQDesign.Spacing.sm) {
                    Image(systemName: viewModel.selectedVideoData != nil ? "arrow.triangle.2.circlepath" : "video.fill")
                        .font(.system(size: 16))
                    Text(viewModel.selectedVideoData != nil ? "Choose Different" : "Select Video")
                        .font(BQDesign.Typography.bodyBold)
                }
                .foregroundColor(BQDesign.Colors.primaryPurple)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                        .stroke(BQDesign.Colors.primaryPurple, lineWidth: 1.5)
                )
            }
            
            submitButton
        }
    }
    
    // MARK: Text Submission
    var textSubmission: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            TextField("Write your proof here...", text: $viewModel.textProof, axis: .vertical)
                .font(BQDesign.Typography.body)
                .foregroundColor(BQDesign.Colors.textPrimary)
                .tint(BQDesign.Colors.primaryPurple)
                .lineLimit(3...8)
                .padding(BQDesign.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                        .fill(BQDesign.Colors.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                        .stroke(BQDesign.Colors.textTertiary.opacity(0.3), lineWidth: 1)
                )
            
            submitButton
        }
    }
    
    // MARK: Button Submission
    var buttonSubmission: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            Text("Friends verified this one?")
                .font(BQDesign.Typography.caption)
                .foregroundColor(BQDesign.Colors.textSecondary)
            
            submitButton
        }
    }
    
    // MARK: Submit Button
    var submitButton: some View {
        Button {
            Task { await viewModel.submit() }
        } label: {
            HStack(spacing: BQDesign.Spacing.sm) {
                if viewModel.isSubmitting {
                    ProgressView().tint(.white)
                } else if viewModel.submitSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                    Text("Done!")
                        .font(BQDesign.Typography.bodyBold)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16))
                    Text("Submit & Earn ✦ \(challenge.pointValue)")
                        .font(BQDesign.Typography.bodyBold)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                viewModel.submitSuccess
                ? AnyShapeStyle(BQDesign.Colors.success)
                : AnyShapeStyle(BQDesign.Colors.primaryGradient)
            )
            .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous))
        }
        .disabled(!viewModel.canSubmit)
        .opacity(viewModel.canSubmit || viewModel.submitSuccess ? 1 : 0.5)
    }
    
    // MARK: Completed Banner
    var completedBanner: some View {
        HStack(spacing: BQDesign.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(BQDesign.Colors.success)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Challenge Complete!")
                    .font(BQDesign.Typography.bodyBold)
                    .foregroundColor(BQDesign.Colors.textPrimary)
                Text("+\(challenge.pointValue) ✦ earned")
                    .font(BQDesign.Typography.caption)
                    .foregroundColor(BQDesign.Colors.gold)
            }
            
            Spacer()
        }
        .padding(BQDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                .fill(BQDesign.Colors.success.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                        .stroke(BQDesign.Colors.success.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: Timeline Button
    var timelineButton: some View {
        Button {
            onDismiss()
            // Small delay so sheet dismisses before tab switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                session.navigateToTimeline()
            }
        } label: {
            HStack(spacing: BQDesign.Spacing.sm) {
                Text("Check out your timeline")
                    .font(BQDesign.Typography.bodyBold)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, BQDesign.Spacing.lg)
            .padding(.vertical, BQDesign.Spacing.md)
            .background(
                Capsule().fill(BQDesign.Colors.primaryGradient)
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(BQDesign.Animation.bouncy, value: viewModel.showTimelinePrompt)
    }
    
    // MARK: Gradient Helper
    var categoryGradient: LinearGradient {
        switch challenge.category {
        case .physical:
            return LinearGradient(colors: [Color(hex: "4CAF50"), Color(hex: "66BB6A")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .social:
            return LinearGradient(colors: [Color(hex: "5B9FE6"), Color(hex: "7BB3ED")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .creative:
            return LinearGradient(colors: [BQDesign.Colors.primaryPurple, BQDesign.Colors.primaryPink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .sentimental:
            return LinearGradient(colors: [BQDesign.Colors.primaryPink, Color(hex: "FF8FB1")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .adventure:
            return LinearGradient(colors: [BQDesign.Colors.primaryOrange, Color(hex: "FFB74D")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
