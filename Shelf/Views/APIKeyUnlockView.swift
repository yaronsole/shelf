import SwiftUI

struct APIKeyUnlockView: View {
    @Environment(AppStateManager.self) var appState
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var selectedProvider: LLMProvider = .claude
    @State private var isSaving = false

    private var canUnlock: Bool { apiKey.trimmingCharacters(in: .whitespaces).count > 10 }

    var body: some View {
        ZStack {
            Color(hex: "1C1C1E").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Hero text
                    VStack(alignment: .leading, spacing: 10) {
                        Text("You've got good taste.")
                            .font(.custom("Georgia", size: 28)).bold()
                            .foregroundStyle(.white)

                        Text("Ready for the real thing? Connect your API key to unlock unlimited recommendations.")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // What is an API key?
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's an API key?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "D4AF37"))

                        Text("It's like a password that lets Shelf talk to Claude, the AI behind your recommendations. You own it, and it only lives on your device.")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(Color(hex: "2C2C2E"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Get key link
                    Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                        HStack {
                            Text("Get a free Claude API key →")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: "D4AF37"))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(Color(hex: "D4AF37").opacity(0.7))
                        }
                        .padding(14)
                        .background(Color(hex: "2C2C2E"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Provider + key input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI Provider")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))

                        Picker("Provider", selection: $selectedProvider) {
                            ForEach(LLMProvider.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(Color(hex: "D4AF37"))

                        Text("Paste your API key")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 4)

                        TextField("sk-ant-...", text: $apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color(hex: "2C2C2E"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        canUnlock ? Color(hex: "D4AF37").opacity(0.5) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }

                    // Unlock button
                    Button {
                        guard canUnlock else { return }
                        isSaving = true
                        appState.saveAPIKey(apiKey.trimmingCharacters(in: .whitespaces),
                                            provider: selectedProvider)
                        dismiss()
                    } label: {
                        Text(isSaving ? "Unlocking…" : "Unlock Shelf")
                    }
                    .buttonStyle(ShelfPrimaryButtonStyle(isEnabled: canUnlock))
                    .disabled(!canUnlock || isSaving)

                    // Privacy note
                    HStack {
                        Spacer()
                        Label("Your key is stored only on your device. Never shared.", systemImage: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }

                    // Dismiss without unlocking — returns to demo
                    Button {
                        dismiss()
                    } label: {
                        Text("Continue exploring demo mode")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
            }
        }
    }
}
