import SwiftUI
import UIKit

// MARK: - TasteSetupView

struct TasteSetupView: View {
    @Environment(AppStateManager.self) var appState

    @State private var selectedLabels: Set<String> = []
    @State private var reactionLine: String? = nil

    private var canContinue: Bool { selectedLabels.count >= 2 }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(hex: "1C1C1E").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 8) {
                        Text("What kind of reader are you?")
                            .font(.custom("Georgia", size: 26)).bold()
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text("Pick at least 2. Pick all of them. No judgment.")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)

                        // Taste reaction line
                        if let line = reactionLine {
                            Text(line)
                                .font(.custom("Georgia", size: 14)).italic()
                                .foregroundStyle(Color(hex: "D4AF37"))
                                .multilineTextAlignment(.center)
                                .padding(.top, 6)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 56)
                    .padding(.bottom, 24)

                    // Vibe grid
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ForEach(vibeOptions) { vibe in
                            VibeTile(
                                vibe: vibe,
                                isSelected: selectedLabels.contains(vibe.label)
                            ) {
                                toggleVibe(vibe)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 140) // space for fixed button
                }
            }

            // Fixed bottom CTA
            VStack(spacing: 0) {
                // Gradient fade
                LinearGradient(
                    colors: [Color(hex: "1C1C1E").opacity(0), Color(hex: "1C1C1E")],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 40)

                Button {
                    guard canContinue else { return }
                    completeTasteSetup()
                } label: {
                    Text(canContinue ? "Build my shelf →" : "Pick at least 2 vibes")
                }
                .buttonStyle(ShelfPrimaryButtonStyle(isEnabled: canContinue))
                .disabled(!canContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .padding(.top, 8)
                .background(Color(hex: "1C1C1E"))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: reactionLine)
    }

    // MARK: - Actions

    private func toggleVibe(_ vibe: VibeOption) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            if selectedLabels.contains(vibe.label) {
                selectedLabels.remove(vibe.label)
            } else {
                selectedLabels.insert(vibe.label)
            }
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            reactionLine = selectedLabels.count >= 2
                ? tasteReactionLine(for: selectedLabels)
                : nil
        }
    }

    private func completeTasteSetup() {
        // Collect seed books from selected vibes (deduplicated)
        let seedTitles = Array(Set(
            selectedLabels.flatMap { label in
                vibeOptions.first(where: { $0.label == label })?.seedBooks ?? []
            }
        ))
        UserDefaults.standard.set(seedTitles, forKey: "seedBookTitles")
        UserDefaults.standard.set(Array(selectedLabels), forKey: "selectedVibeLabels")

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        appState.completeTasteSetup()
    }
}

// MARK: - VibeTile

struct VibeTile: View {
    let vibe: VibeOption
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Text(vibe.emoji).font(.system(size: 28))

                    Text(vibe.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(vibe.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelected
                              ? vibe.color.opacity(0.9)
                              : Color(hex: "2C2C2E"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    isSelected ? Color(hex: "D4AF37") : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                )

                // Checkmark badge
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "D4AF37"))
                        .font(.system(size: 18))
                        .padding(8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }
}
