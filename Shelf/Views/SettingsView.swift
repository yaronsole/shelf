import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStateManager.self) var appState
    @Environment(MilestoneManager.self) var milestones

    @Query private var seedBooks: [SeedBook]
    @Query private var reactions: [Reaction]
    @Query private var purchases: [Purchase]

    @State private var apiKey: String = ""
    @State private var selectedProvider: LLMProvider = .claude
    @State private var showResetAlert = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                // Taste Profile card
                Section {
                    TasteProfileView()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                // API Key
                Section("AI Provider") {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(LLMProvider.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    SecureField("API Key", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button(saved ? "Saved ✓" : "Save API Key") {
                        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
                        appState.saveAPIKey(trimmed, provider: selectedProvider)
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                    }
                    .disabled(apiKey.isEmpty)
                }

                // Taste Profile Stats
                Section("Your Shelf") {
                    LabeledContent("Total Reactions", value: "\(reactions.count)")
                    LabeledContent("Books Liked", value: "\(milestones.totalLikes)")
                    LabeledContent("Books Passed", value: "\(milestones.totalPasses)")
                    LabeledContent("Books Purchased", value: "\(purchases.count)")
                    let positives = reactions.filter { $0.type == .thumbsUp || $0.type == .alreadyReadLiked }.count
                    let negatives = reactions.filter { $0.type == .thumbsDown || $0.type == .alreadyReadDisliked }.count
                    LabeledContent("Positive Signals", value: "\(positives)")
                    LabeledContent("Negative Signals", value: "\(negatives)")
                }

                // Seed Books
                if !seedBooks.isEmpty {
                    Section("Seed Books") {
                        ForEach(seedBooks) { book in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.title).font(.subheadline.bold())
                                Text(book.author).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Danger Zone
                Section("Data") {
                    Button("Reset All Data", role: .destructive) {
                        showResetAlert = true
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                apiKey = appState.apiKey
                selectedProvider = appState.selectedProvider
            }
            .alert("Reset All Data?", isPresented: $showResetAlert) {
                Button("Reset", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all your seed books, reactions, purchases, and recommendations. This cannot be undone.")
            }
        }
    }

    private func resetAll() {
        // Reset app state (UserDefaults) and Keychain
        appState.resetAll()
        Keychain.delete(key: .llmAPIKey)
        Keychain.delete(key: .llmProvider)

        // Reset milestones
        milestones.reset()

        // Clear extra UserDefaults keys
        for key in ["selectedVibeLabels", "hasSeenFirstRecommendations", "lastOpenDate"] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // Delete SwiftData models
        try? modelContext.delete(model: SeedBook.self)
        try? modelContext.delete(model: ShownBook.self)
        try? modelContext.delete(model: Reaction.self)
        try? modelContext.delete(model: Purchase.self)
        try? modelContext.delete(model: WishlistItem.self)
        try? modelContext.save()
    }
}
