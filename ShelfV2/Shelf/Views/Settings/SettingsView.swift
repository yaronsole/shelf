import SwiftUI
import SwiftData

/// Settings & legal sheet — reached from a subtle gear in the Taste tab.
/// Hosts the community contribution toggle, the AI-usage disclosure, the privacy
/// policy link, and the "delete my data" control. Plain `Form` so it reads as a
/// native iOS settings screen; no change to any existing surface.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    // Local mirror of the server-side contribute flag for instant display.
    @AppStorage("com.ysole.shelf.contribute") private var contribute = true

    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text(Strings.Settings.contributeFooter)) {
                    Toggle(Strings.Settings.contributeTitle, isOn: $contribute)
                }

                Section(Strings.Settings.aboutHeader) {
                    NavigationLink(Strings.Settings.aiRow) { AIDisclosureView() }
                    Button(Strings.Settings.privacyRow) {
                        if let url = URL(string: AppLinks.privacyPolicyURL) { openURL(url) }
                    }
                    .tint(.primary)
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text(Strings.Settings.deleteButton)
                        }
                    }
                    .disabled(isDeleting)
                }
            }
            .navigationTitle(Strings.Settings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.secondaryLabel))
                            .font(.title3)
                    }
                }
            }
            .task {
                // Reconcile the toggle with the server's stored value (best effort).
                if let s = try? await APIClient.shared.fetchUserSettings() {
                    contribute = s.contribute
                }
            }
            .onChange(of: contribute) { _, newValue in
                Task { try? await APIClient.shared.updateUserSettings(contribute: newValue) }
            }
            .alert(Strings.Settings.deleteAlertTitle, isPresented: $showDeleteConfirm) {
                Button(Strings.Settings.deleteConfirm, role: .destructive) { performDelete() }
                Button(Strings.Common.cancel, role: .cancel) {}
            } message: {
                Text(Strings.Settings.deleteAlertMessage)
            }
            .alert(Strings.Settings.deleteFailed, isPresented: $deleteFailed) {
                Button(Strings.Common.cancel, role: .cancel) {}
            }
        }
    }

    /// Hard-delete: server purge first (while the token is still valid), then
    /// local SwiftData + token/flags. If the server call fails we keep everything
    /// so the user can retry — never strand server data behind a discarded token.
    private func performDelete() {
        isDeleting = true
        Task {
            do {
                try await APIClient.shared.deleteUserData()
            } catch {
                await MainActor.run { isDeleting = false; deleteFailed = true }
                return
            }
            await MainActor.run {
                try? modelContext.delete(model: CachedRecommendation.self)
                try? modelContext.delete(model: ReadingListItem.self)
                try? modelContext.delete(model: LocalSeedBook.self)
                appState.resetAll()   // clears token, onboarding, consent → fresh user
                isDeleting = false
                dismiss()
            }
        }
    }
}

/// Read-only disclosure shown from Settings. Same copy as the first-run consent.
struct AIDisclosureView: View {
    var body: some View {
        ScrollView {
            Text(Strings.Settings.aiDisclosureBody)
                .font(.body)
                .foregroundStyle(Color(.label))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .navigationTitle(Strings.Settings.aiDisclosureTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// First-run AI-usage disclosure + consent. Gated ahead of onboarding/main in
/// RootView until `aiConsentAcknowledged` is set. Apple (2026) requires apps
/// using an external AI service to disclose it and obtain consent.
struct AIConsentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(Strings.Settings.aiDisclosureTitle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(Strings.Settings.aiDisclosureBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(Strings.Settings.privacyRow) {
                if let url = URL(string: AppLinks.privacyPolicyURL) { openURL(url) }
            }
            .font(.subheadline)
            Spacer()
            Button {
                appState.aiConsentAcknowledged = true
            } label: {
                Text(Strings.Settings.consentContinue)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
