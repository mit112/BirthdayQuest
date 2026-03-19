import SwiftUI
import PhotosUI
import ConfettiSwiftUI

struct ChallengeDetailView: View {
    
    let challenge: Challenge
    let onDismiss: () -> Void
    
    @EnvironmentObject private var session: SessionManager
    @StateObject private var viewModel: ChallengeSubmissionViewModel
    @State private var confettiTrigger = 0
    @State private var selectedOption: Int = 0 // For 2-in-1: 0 = option A, 1 = option B
    
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
                    
                    // 2-in-1 option picker (if applicable)
                    if challenge.isTwoInOne {
                        twoInOnePicker
                    }
                    
                    // Info section
                    infoSection
                    
                    // Submission area
                    if challenge.isCompleted || viewModel.submitSuccess {
                        completedBanner
                        proofSection
                    } else {
                        submissionSection
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
            Task { await viewModel.handlePhotoSelection() }
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
    
    // MARK: 2-in-1 Option Picker
    var twoInOnePicker: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(BQDesign.Colors.primaryOrange)
                Text("2-in-1 Challenge")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(BQDesign.Colors.primaryOrange)
            }
            
            HStack(spacing: 10) {
                optionTab(label: "Option A", index: 0)
                optionTab(label: "Option B", index: 1)
            }
        }
    }
    
    func optionTab(label: String, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedOption = index
            }
            BQDesign.Haptics.selection()
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(selectedOption == index ? .white : BQDesign.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                        .fill(selectedOption == index
                              ? AnyShapeStyle(BQDesign.Colors.primaryGradient)
                              : AnyShapeStyle(BQDesign.Colors.cardBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                        .stroke(
                            selectedOption == index
                            ? Color.clear
                            : BQDesign.Colors.textTertiary.opacity(0.2),
                            lineWidth: 1
                        )
                )
        }
    }
    
    // MARK: Info
    var infoSection: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            // Show option A or B title/description based on selection
            if challenge.isTwoInOne && selectedOption == 1,
               let bTitle = challenge.optionBTitle,
               let bDesc = challenge.optionBDescription {
                Text(bTitle)
                    .font(BQDesign.Typography.screenTitle)
                    .foregroundColor(BQDesign.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.2), value: selectedOption)
                
                Text(bDesc)
                    .font(BQDesign.Typography.body)
                    .foregroundColor(BQDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.2), value: selectedOption)
            } else {
                Text(challenge.title)
                    .font(BQDesign.Typography.screenTitle)
                    .foregroundColor(BQDesign.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.2), value: selectedOption)
                
                Text(challenge.description)
                    .font(BQDesign.Typography.body)
                    .foregroundColor(BQDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.2), value: selectedOption)
            }
            
            // Metadata row — points + difficulty (no more submission type column)
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
    
    // MARK: Submission Section — Universal 3-option UI
    @ViewBuilder
    var submissionSection: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            Text("Submit Proof")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
            
            // Submission type selector
            submissionTypePicker
            
            // Content area based on selected type
            switch viewModel.selectedSubmissionType {
            case .photo:
                photoSubmission
            case .text:
                textSubmission
            case .button:
                buttonSubmission
            }
        }
    }
    
    // MARK: Submission Type Picker
    var submissionTypePicker: some View {
        HStack(spacing: 8) {
            ForEach(SubmissionType.allCases, id: \.self) { type in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.selectedSubmissionType = type
                    }
                    BQDesign.Haptics.selection()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: type.icon)
                            .font(.system(size: 13))
                        Text(type.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(
                        viewModel.selectedSubmissionType == type
                        ? .white
                        : BQDesign.Colors.textSecondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                            .fill(
                                viewModel.selectedSubmissionType == type
                                ? AnyShapeStyle(BQDesign.Colors.primaryGradient)
                                : AnyShapeStyle(BQDesign.Colors.cardBackground)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.md, style: .continuous)
                            .stroke(
                                viewModel.selectedSubmissionType == type
                                ? Color.clear
                                : BQDesign.Colors.textTertiary.opacity(0.2),
                                lineWidth: 1
                            )
                    )
                }
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
                    Image(systemName: viewModel.previewImage != nil ? "arrow.triangle.2.circlepath" : "camera.fill")
                        .font(.system(size: 16))
                    Text(viewModel.previewImage != nil ? "Choose Different" : "Select Photo")
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
    
    // MARK: Proof Section
    @ViewBuilder
    var proofSection: some View {
        let type = challenge.proofType ?? "button"
        
        VStack(spacing: BQDesign.Spacing.sm) {
            Text("Your Proof")
                .font(BQDesign.Typography.sectionTitle)
                .foregroundColor(BQDesign.Colors.textPrimary)
            
            if type == "photo" {
                photoProofView
            } else if type == "text" {
                textProofView
            } else {
                buttonProofView
            }
        }
    }
    
    // MARK: Photo Proof
    var photoProofView: some View {
        Group {
            if let localImage = viewModel.previewImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous))
                    .bqShadow(BQDesign.Shadows.card)
            } else if let urlString = challenge.proofUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous))
                            .bqShadow(BQDesign.Shadows.card)
                    case .failure:
                        proofPlaceholder(icon: "photo", text: "Couldn't load photo")
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                            .background(
                                RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                                    .fill(BQDesign.Colors.cardBackground)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                proofPlaceholder(icon: "camera.fill", text: "Photo submitted")
            }
        }
    }
    
    // MARK: Text Proof
    var resolvedProofText: String? {
        if !viewModel.textProof.isEmpty { return viewModel.textProof }
        if let pt = challenge.proofText, !pt.isEmpty { return pt }
        return nil
    }
    
    var textProofView: some View {
        Group {
            if let text = resolvedProofText {
                VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
                    HStack(spacing: BQDesign.Spacing.xs) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 14))
                            .foregroundColor(BQDesign.Colors.primaryPurple)
                        Text("Your response")
                            .font(BQDesign.Typography.caption)
                            .foregroundColor(BQDesign.Colors.textSecondary)
                    }
                    
                    Text(text)
                        .font(BQDesign.Typography.body)
                        .foregroundColor(BQDesign.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(BQDesign.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                        .fill(BQDesign.Colors.cardBackground)
                )
                .bqShadow(BQDesign.Shadows.card)
            } else {
                proofPlaceholder(icon: "text.cursor", text: "Text submitted")
            }
        }
    }
    
    // MARK: Button Proof
    var buttonProofView: some View {
        HStack(spacing: BQDesign.Spacing.sm) {
            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: 20))
                .foregroundColor(BQDesign.Colors.primaryPurple)
            Text("Verified by friends")
                .font(BQDesign.Typography.body)
                .foregroundColor(BQDesign.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(BQDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                .fill(BQDesign.Colors.cardBackground)
        )
        .bqShadow(BQDesign.Shadows.card)
    }
    
    // MARK: Proof Placeholder
    func proofPlaceholder(icon: String, text: String) -> some View {
        HStack(spacing: BQDesign.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(BQDesign.Colors.textTertiary)
            Text(text)
                .font(BQDesign.Typography.body)
                .foregroundColor(BQDesign.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(BQDesign.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                .fill(BQDesign.Colors.cardBackground)
        )
        .bqShadow(BQDesign.Shadows.card)
    }
    
    // MARK: Timeline Button
    var timelineButton: some View {
        Button {
            onDismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
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
