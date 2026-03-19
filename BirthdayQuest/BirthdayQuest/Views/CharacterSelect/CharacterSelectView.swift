import SwiftUI

struct CharacterSelectView: View {
    
    @EnvironmentObject private var session: SessionManager
    @StateObject private var viewModel = CharacterSelectViewModel()
    
    // MARK: - Animation State
    @State private var appeared = false
    @State private var titleGlow = false
    @State private var buttonScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // MARK: - Background
            backgroundLayer
            
            // MARK: - Content
            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                // Title
                titleSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : -15)
                
                Spacer()
                
                // Character carousel
                characterCarousel
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.9)
                
                Spacer()
                
                // Navigation dots
                dotIndicators
                    .padding(.bottom, BQDesign.Spacing.lg)
                
                // "This is me" button
                claimButton
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 30)
                
                Spacer().frame(height: 50)
            }
        }
        .onAppear {
            viewModel.startListening()
            withAnimation(BQDesign.Animation.smooth.delay(0.2)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(0.5)) {
                titleGlow = true
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .alert("Oops", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong")
        }
    }
}

// MARK: - Subviews

private extension CharacterSelectView {
    
    // MARK: Background
    var backgroundLayer: some View {
        ZStack {
            // Deep rich gradient
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "0F0A1F"), location: 0.0),
                    .init(color: Color(hex: "1A1040"), location: 0.25),
                    .init(color: Color(hex: "251660"), location: 0.5),
                    .init(color: Color(hex: "1A1040"), location: 0.75),
                    .init(color: Color(hex: "0F0A1F"), location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Ambient bokeh orbs
            CharacterSelectBokehView()
            
            // Twinkling stars
            CharacterSelectStarsView()
        }
    }
    
    // MARK: Title
    var titleSection: some View {
        VStack(spacing: BQDesign.Spacing.sm) {
            Text("Choose Your Character")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Swipe to find yourself")
                .font(BQDesign.Typography.body)
                .foregroundColor(.white.opacity(titleGlow ? 0.55 : 0.35))
        }
        .padding(.horizontal, BQDesign.Spacing.lg)
    }
    
    // MARK: Character Carousel
    var characterCarousel: some View {
        TabView(selection: $viewModel.selectedIndex) {
            ForEach(Array(viewModel.characters.enumerated()), id: \.element.id) { index, character in
                CharacterCardView(
                    character: character,
                    isSelected: viewModel.selectedIndex == index
                )
                .tag(index)
                .padding(.horizontal, BQDesign.Spacing.xl)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 420)
        .onChange(of: viewModel.selectedIndex) { _, _ in
            BQDesign.Haptics.selection()
        }
    }
    
    // MARK: Dot Indicators
    var dotIndicators: some View {
        HStack(spacing: 10) {
            ForEach(viewModel.characters.indices, id: \.self) { index in
                let isActive = index == viewModel.selectedIndex
                let isClaimed = viewModel.characters.indices.contains(index)
                    && viewModel.characters[index].claimed
                
                Circle()
                    .fill(
                        isActive
                        ? Color.white
                        : isClaimed
                            ? Color.white.opacity(0.15)
                            : Color.white.opacity(0.35)
                    )
                    .frame(width: isActive ? 10 : 7, height: isActive ? 10 : 7)
                    .shadow(color: isActive ? .white.opacity(0.4) : .clear, radius: 4)
                    .animation(BQDesign.Animation.snappy, value: viewModel.selectedIndex)
            }
        }
    }
    
    // MARK: Claim Button
    var claimButton: some View {
        Button {
            Task {
                await viewModel.handleClaimTap(session: session)
            }
        } label: {
            HStack(spacing: BQDesign.Spacing.sm) {
                if viewModel.isClaiming {
                    ProgressView()
                        .tint(.white)
                } else if viewModel.selectedIsClaimed {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Override")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                } else {
                    Text("This is me")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                Group {
                    if viewModel.isClaiming {
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else if viewModel.selectedIsClaimed {
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.08)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        LinearGradient(
                            colors: [
                                BQDesign.Colors.primaryPurple,
                                BQDesign.Colors.primaryPink
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        viewModel.selectedIsClaimed || viewModel.isClaiming
                            ? Color.white.opacity(0.08)
                            : Color.white.opacity(0.2),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: !viewModel.selectedIsClaimed && !viewModel.isClaiming
                    ? BQDesign.Colors.primaryPurple.opacity(0.4)
                    : Color.clear,
                radius: 16, y: 4
            )
            .scaleEffect(buttonScale)
            .padding(.horizontal, BQDesign.Spacing.xl)
        }
        .disabled(!viewModel.canClaim)
        .pressAnimation(scale: $buttonScale)
        // PIN bypass alert
        .alert("Override Character", isPresented: $viewModel.showPinPrompt) {
            SecureField("Enter PIN", text: $viewModel.pinInput)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                Task { await viewModel.submitPin(session: session) }
            }
        } message: {
            Text(viewModel.showPinError
                 ? "Wrong PIN. Try again."
                 : "This character is already claimed. Enter the override PIN to switch.")
        }
    }
}

// MARK: - Character Select Bokeh (ambient orbs)

private struct CharacterSelectBokehView: View {
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<6, id: \.self) { i in
                CharSelectBokehOrb(index: i, bounds: geo.size)
            }
        }
        .ignoresSafeArea()
    }
}

private struct CharSelectBokehOrb: View {
    let index: Int
    let bounds: CGSize
    
    @State private var drift: CGSize = .zero
    @State private var opacity: Double = 0
    
    private var config: (CGFloat, CGFloat, CGFloat, Color, Double) {
        let configs: [(CGFloat, CGFloat, CGFloat, Color, Double)] = [
            (0.2, 0.3, 80, Color(hex: "7C5CFC"), 0.06),
            (0.8, 0.2, 60, Color(hex: "FF6B9D"), 0.05),
            (0.5, 0.7, 100, Color(hex: "7C5CFC"), 0.07),
            (0.15, 0.8, 50, Color(hex: "FFA45B"), 0.04),
            (0.85, 0.6, 70, Color(hex: "FF6B9D"), 0.05),
            (0.5, 0.15, 90, Color(hex: "A78BFA"), 0.06),
        ]
        return configs[index % configs.count]
    }
    
    var body: some View {
        let (xFrac, yFrac, size, color, baseOpacity) = config
        
        Circle()
            .fill(color.opacity(baseOpacity))
            .frame(width: size, height: size)
            .blur(radius: size * 0.35)
            .position(x: xFrac * bounds.width, y: yFrac * bounds.height)
            .offset(drift)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: 1.5).delay(Double(index) * 0.2)) {
                    opacity = 1
                }
                withAnimation(
                    .easeInOut(duration: Double.random(in: 6...10))
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.3)
                ) {
                    drift = CGSize(
                        width: CGFloat.random(in: -25...25),
                        height: CGFloat.random(in: -20...20)
                    )
                }
            }
    }
}

// MARK: - Character Select Stars (twinkling dots)

private struct CharacterSelectStarsView: View {
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<25, id: \.self) { i in
                CharSelectStar(index: i, bounds: geo.size)
            }
        }
        .ignoresSafeArea()
    }
}

private struct CharSelectStar: View {
    let index: Int
    let bounds: CGSize
    
    @State private var twinkle = false
    
    private var x: CGFloat {
        CGFloat((Double(index) * 37.7).truncatingRemainder(dividingBy: Double(bounds.width)))
    }
    private var y: CGFloat {
        CGFloat((Double(index) * 53.3).truncatingRemainder(dividingBy: Double(bounds.height)))
    }
    private var size: CGFloat {
        CGFloat([1.5, 2.0, 2.5, 1.8, 3.0][index % 5])
    }
    
    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .position(x: x, y: y)
            .opacity(twinkle ? 0.7 : 0.1)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: Double.random(in: 1.5...3.5))
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.15)
                ) {
                    twinkle = true
                }
            }
    }
}
