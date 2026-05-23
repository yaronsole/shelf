import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var debugTapCount = 0
    @State private var showDebug = false
    @State private var debugInfo: DebugInfoDTO? = nil
    @State private var isLoadingDebug = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Link(Strings.Settings.about, destination: URL(string: "https://apps.apple.com/app/shelf")!)
                    Link(Strings.Settings.feedback, destination: URL(string: "mailto:feedback@shelf.app")!)
                }

                Section("Legal") {
                    Link(Strings.Settings.privacy, destination: URL(string: "https://github.com/ysole/shelf/blob/main/PRIVACY.md")!)
                    Link(Strings.Settings.terms, destination: URL(string: "https://github.com/ysole/shelf/blob/main/TERMS.md")!)
                }

                Section {
                    versionRow
                }

                if showDebug {
                    debugSection
                }
            }
            .navigationTitle(Strings.Settings.tabTitle)
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Version Row (tap 5× to reveal debug — SET-03)

    private var versionRow: some View {
        HStack {
            Text(Strings.Settings.versionPrefix)
            Spacer()
            Text(appVersionString)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            debugTapCount += 1
            if debugTapCount >= 5 {
                showDebug = true
                loadDebugInfo()
                debugTapCount = 0
            }
        }
    }

    // MARK: - Debug Section (SET-03)

    private var debugSection: some View {
        Section(Strings.Settings.debugSectionTitle) {
            if isLoadingDebug {
                HStack {
                    ProgressView()
                    Text(Strings.Common.loading).foregroundStyle(.secondary)
                }
            } else if let info = debugInfo {
                LabeledContent(Strings.Settings.lastGeneration) {
                    Text(info.lastGenerationTimestamp.map { formatted($0) } ?? Strings.Settings.never)
                        .foregroundStyle(.secondary)
                }
                LabeledContent(Strings.Settings.batchSize) {
                    Text(info.lastBatchSize.map { "\($0)" } ?? Strings.Settings.never)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Could not load debug info.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func loadDebugInfo() {
        isLoadingDebug = true
        Task {
            let info = try? await APIClient.shared.fetchDebugInfo()
            await MainActor.run {
                self.debugInfo = info
                self.isLoadingDebug = false
            }
        }
    }
}
