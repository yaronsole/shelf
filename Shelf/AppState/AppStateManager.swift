import Foundation
import SwiftUI

// MARK: - OnboardingStage

enum OnboardingStage {
    case preview      // 3-screen visual tease (first launch only)
    case tasteSetup   // Vibe/genre selection
    case demo         // Taste set up, no API key yet
    case live         // API key entered, full experience
}

// MARK: - AppStateManager

@Observable
final class AppStateManager {
    var stage: OnboardingStage = .preview
    var hasCompletedPreview: Bool = false
    var hasCompletedTasteSetup: Bool = false
    var apiKey: String = ""
    var selectedProvider: LLMProvider = .claude

    init() {
        self.hasCompletedPreview = UserDefaults.standard.bool(forKey: "hasCompletedPreview")
        self.hasCompletedTasteSetup = UserDefaults.standard.bool(forKey: "hasCompletedTasteSetup")
        self.apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        let providerRaw = UserDefaults.standard.string(forKey: "selectedProvider") ?? LLMProvider.claude.rawValue
        self.selectedProvider = LLMProvider(rawValue: providerRaw) ?? .claude
        self.stage = computeStage()
    }

    func computeStage() -> OnboardingStage {
        if !hasCompletedPreview { return .preview }
        if !hasCompletedTasteSetup { return .tasteSetup }
        if apiKey.isEmpty { return .demo }
        return .live
    }

    func completePreview() {
        hasCompletedPreview = true
        UserDefaults.standard.set(true, forKey: "hasCompletedPreview")
        stage = computeStage()
    }

    func completeTasteSetup() {
        hasCompletedTasteSetup = true
        UserDefaults.standard.set(true, forKey: "hasCompletedTasteSetup")
        stage = computeStage()
    }

    func saveAPIKey(_ key: String, provider: LLMProvider) {
        apiKey = key
        selectedProvider = provider
        UserDefaults.standard.set(key, forKey: "apiKey")
        UserDefaults.standard.set(provider.rawValue, forKey: "selectedProvider")
        // Also keep the Keychain in sync so LLMService still works
        Keychain.save(key: .llmAPIKey, value: key)
        Keychain.save(key: .llmProvider, value: provider.rawValue)
        stage = .live
    }

    /// Call this to wipe all state (e.g. from Settings "Reset All Data")
    func resetAll() {
        hasCompletedPreview = false
        hasCompletedTasteSetup = false
        apiKey = ""
        UserDefaults.standard.removeObject(forKey: "hasCompletedPreview")
        UserDefaults.standard.removeObject(forKey: "hasCompletedTasteSetup")
        UserDefaults.standard.removeObject(forKey: "apiKey")
        UserDefaults.standard.removeObject(forKey: "selectedProvider")
        UserDefaults.standard.removeObject(forKey: "seedBookTitles")
        stage = computeStage()
    }
}
