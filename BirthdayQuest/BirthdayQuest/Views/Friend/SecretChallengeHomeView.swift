import SwiftUI

struct SecretChallengeHomeView: View {
    
    @EnvironmentObject private var session: SessionManager
    @StateObject private var viewModel = SecretChallengeViewModel()
    @State private var appeared = false
    
    var body: some View {
        ZStack {
            // Dark spy background
            BQDesign.Colors.secretGradient.ignoresSafeArea()
            
            // Scan-line overlay
            scanLines
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: BQDesign.Spacing.lg) {
                    // Header
                    headerSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : -15)
                    
                    // Status badge
                    statusBadge
                        .opacity(appeared ? 1 : 0)
                    
                    if viewModel.isLoading {
                        DossierSkeletonView()
                            .padding(.top, BQDesign.Spacing.md)
                    } else {
                        // The dossier card
                        dossierCard
                            .opacity(appeared ? 1 : 0)
                            .scaleEffect(appeared ? 1 : 0.95)
                        
                        // Action buttons
                        actionButtons
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                    }
                    
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, BQDesign.Spacing.lg)
                .padding(.top, BQDesign.Spacing.xl)
            }
        }
        .onAppear {
            viewModel.loadExisting()
            withAnimation(BQDesign.Animation.smooth.delay(0.15)) {
                appeared = true
            }
        }
        .onDisappear { viewModel.stopListening() }
        .alert("Oops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong")
        }
    }
}

// MARK: - Subviews

private extension SecretChallengeHomeView {
    
    // MARK: Header
    var headerSection: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            AvatarView(name: session.currentUser?.name ?? "Agent", size: 60)
            
            Text("Your Secret Dare")
                .font(BQDesign.Typography.heroTitle)
                .foregroundColor(.white)
            
            Text("for \(CharacterID.birthdayBoyName)")
                .font(BQDesign.Typography.body)
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    // MARK: Status Badge
    var statusBadge: some View {
        Text(viewModel.statusText)
            .font(BQDesign.Typography.caption)
            .foregroundColor(BQDesign.Colors.secretAccent)
            .padding(.horizontal, BQDesign.Spacing.md)
            .padding(.vertical, BQDesign.Spacing.sm)
            .background(
                Capsule()
                    .fill(BQDesign.Colors.secretAccent.opacity(0.15))
                    .overlay(
                        Capsule().stroke(BQDesign.Colors.secretAccent.opacity(0.3), lineWidth: 1)
                    )
            )
    }
    
    // MARK: Dossier Card
    var dossierCard: some View {
        VStack(spacing: BQDesign.Spacing.lg) {
            // "CLASSIFIED" stamp
            Text("C L A S S I F I E D")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(BQDesign.Colors.secretAccent.opacity(0.6))
                .tracking(4)
                .padding(.vertical, BQDesign.Spacing.xs)
                .frame(maxWidth: .infinity)
                .overlay(
                    Rectangle()
                        .fill(BQDesign.Colors.secretAccent.opacity(0.2))
                        .frame(height: 1),
                    alignment: .bottom
                )
            
            // Title field
            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                Text("MISSION NAME")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                
                TextField("", text: $viewModel.title, prompt:
                    Text("e.g. The Stranger Selfie")
                        .foregroundColor(.white.opacity(0.25))
                )
                    .font(BQDesign.Typography.cardTitle)
                    .foregroundColor(.white)
                    .tint(BQDesign.Colors.secretAccent)
                    .disabled(!viewModel.isEditable)
            }
            
            // Description field
            VStack(alignment: .leading, spacing: BQDesign.Spacing.xs) {
                Text("MISSION BRIEF")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                
                TextField("", text: $viewModel.description, prompt:
                    Text("Describe what he has to do...")
                        .foregroundColor(.white.opacity(0.25)),
                    axis: .vertical
                )
                    .font(BQDesign.Typography.body)
                    .foregroundColor(.white.opacity(0.9))
                    .tint(BQDesign.Colors.secretAccent)
                    .lineLimit(3...6)
                    .disabled(!viewModel.isEditable)
            }
            
            // Point value picker
            VStack(alignment: .leading, spacing: BQDesign.Spacing.sm) {
                Text("REWARD POINTS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                
                HStack(spacing: BQDesign.Spacing.sm) {
                    ForEach(viewModel.pointOptions, id: \.self) { value in
                        Button {
                            viewModel.pointValue = value
                            BQDesign.Haptics.selection()
                        } label: {
                            Text("✦ \(value)")
                                .font(BQDesign.Typography.captionSmall)
                                .fontWeight(.bold)
                                .foregroundColor(
                                    viewModel.pointValue == value
                                    ? BQDesign.Colors.gold : .white.opacity(0.5)
                                )
                                .padding(.horizontal, BQDesign.Spacing.md)
                                .padding(.vertical, BQDesign.Spacing.sm)
                                .background(
                                    Capsule().fill(
                                        viewModel.pointValue == value
                                        ? BQDesign.Colors.gold.opacity(0.2)
                                        : Color.white.opacity(0.08)
                                    )
                                )
                        }
                        .disabled(!viewModel.isEditable)
                    }
                }
            }
        }
        .padding(BQDesign.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: BQDesign.Radius.xl, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: Action Buttons
    var actionButtons: some View {
        VStack(spacing: BQDesign.Spacing.md) {
            // Save button
            if viewModel.isEditable {
                Button {
                    Task { await viewModel.save() }
                } label: {
                    HStack(spacing: BQDesign.Spacing.sm) {
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        } else if viewModel.saveSuccess {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                            Text("Saved!")
                                .font(BQDesign.Typography.bodyBold)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 16, weight: .semibold))
                            Text(viewModel.hasExisting ? "Update Dare" : "Save Dare")
                                .font(BQDesign.Typography.bodyBold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                            .fill(BQDesign.Colors.secretAccent)
                    )
                }
                .disabled(!viewModel.canSave)
                .opacity(viewModel.canSave ? 1 : 0.5)
            }
            
            // Deliver button (only after save, before delivery)
            if viewModel.hasExisting && viewModel.isEditable && !viewModel.isSaving {
                Button {
                    Task { await viewModel.deliver() }
                } label: {
                    HStack(spacing: BQDesign.Spacing.sm) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14))
                        Text("Deliver to Birthday Boy")
                            .font(BQDesign.Typography.bodyBold)
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: BQDesign.Radius.lg, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
            }
        }
    }
    
    // MARK: Scan Lines Overlay
    var scanLines: some View {
        Canvas { context, size in
            let spacing: CGFloat = 4
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.white.opacity(0.015))
                )
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
