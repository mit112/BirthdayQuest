import SwiftUI

struct SecretChallengeHomeView: View {
    
    @EnvironmentObject private var event: EventSession
    @StateObject private var viewModel: SecretChallengeViewModel
    @State private var appeared = false
    @ScaledMetric private var savedCheckmarkIconSize: CGFloat = 16
    @ScaledMetric private var saveIconSize: CGFloat = 16
    @ScaledMetric private var deliverIconSize: CGFloat = 14

    init(eventId: String) {
        _viewModel = StateObject(wrappedValue: SecretChallengeViewModel(eventId: eventId))
    }
    
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
                    
                    switch viewModel.contentState {
                    case .loading:
                        DossierSkeletonView()
                            .padding(.top, BQDesign.Spacing.md)
                    case .failed(let message):
                        // Not the dossier: an editable card would invite the contributor to
                        // write a dare into an occasion that is no longer answering them.
                        ContentFailureView(message: message, onDarkBackground: true)
                            .padding(.top, BQDesign.Spacing.md)
                    case .empty, .ready:
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
            viewModel.loadExisting(userId: event.participant?.id)
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
            AvatarView(avatarId: event.participant?.avatarId ?? AvatarCatalog.fallback, size: 60)
            
            Text("Your Secret Dare")
                .font(BQDesign.Typography.heroTitle)
                .foregroundColor(.white)
            
            Text("for \(event.celebrantName)")
                .font(BQDesign.Typography.body)
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    // MARK: Status Badge
    var statusBadge: some View {
        Text(viewModel.statusText)
            .font(BQDesign.Typography.caption)
            .foregroundColor(statusBadgeColor)
            .accessibilityLabel("Status: \(viewModel.statusText)")
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
    
    /// `secretAccent` on the dark dossier clears the 3:1 bar for graphics but not the 4.5:1
    /// bar for 14pt text. That is pre-existing for the four cheerful statuses and out of
    /// scope to restyle, but the failure status is new copy the user has to act on, so it
    /// gets a foreground that actually passes.
    var statusBadgeColor: Color {
        if case .failed = viewModel.contentState { return .white }
        return BQDesign.Colors.secretAccent
    }

    // MARK: Dossier Card
    var dossierCard: some View {
        VStack(spacing: BQDesign.Spacing.lg) {
            // "CLASSIFIED" stamp
            // No design-system token uses `design: .monospaced`, and it's load-bearing here
            // (the "stamped dossier" look) — falls back to an explicit scalable text style
            // instead of a fixed size, per the same reasoning as the MISSION_* labels below.
            Text("C L A S S I F I E D")
                .font(.system(.caption2, design: .monospaced, weight: .heavy))
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
                // 10pt has no exact Dynamic Type equivalent; .caption2 (11pt) is the nearest
                // built-in style that still scales, so it's reused for the size-10 labels too.
                Text("MISSION NAME")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
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
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                
                TextField("", text: $viewModel.description, prompt:
                    Text("Describe what they have to do...")
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
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
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
                                .font(.system(size: savedCheckmarkIconSize, weight: .bold))
                            Text("Saved!")
                                .font(BQDesign.Typography.bodyBold)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: saveIconSize, weight: .semibold))
                            Text(viewModel.hasExisting ? "Update Dare" : "Save Dare")
                                .font(BQDesign.Typography.bodyBold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
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
                            .font(.system(size: deliverIconSize))
                        Text("Deliver to \(event.celebrantName)")
                            .font(BQDesign.Typography.bodyBold)
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
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
