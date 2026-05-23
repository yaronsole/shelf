# Shelf – Xcode Project Setup Guide

## Creating the Xcode Project

Since Xcode project files (`.pbxproj`) are binary/complex, follow these steps to wire up the source files:

### Step 1: Create New Project
1. Open Xcode → File → New → Project
2. Choose **iOS → App**
3. Set:
   - Product Name: `Shelf`
   - Bundle Identifier: `com.yourname.shelf` (or whatever you prefer)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **SwiftData** ✓
4. Minimum Deployments: **iOS 17.0**

### Step 2: Add Source Files
Delete the default `ContentView.swift` and `Item.swift` that Xcode creates.

Add all the provided `.swift` files into the project:

**Models/**
- `Models.swift`
- `Book.swift`

**Services/**
- `GoogleBooksService.swift`
- `LLMService.swift`
- `NotificationService.swift`

**ViewModels/**
- `RecommendationsViewModel.swift`
- `OnboardingViewModel.swift`

**Views/**
- `OnboardingView.swift`
- `MainTabView.swift`
- `RecommendationsView.swift`
- `WishlistView.swift`
- `SettingsView.swift`

**Root/**
- `ShelfApp.swift` (replace the auto-generated `ShelfApp.swift` content)

### Step 3: Info.plist Additions
In your app target → Info tab, add:
- `NSUserNotificationsUsageDescription` → "Shelf uses notifications to follow up on books you've purchased."

### Step 4: Capabilities
In your app target → Signing & Capabilities:
- No special capabilities needed — Keychain access works without explicit entitlements for basic use
- Push notifications NOT needed (using local notifications only)

### Step 5: Build & Run
The project should build clean on iOS 17+ simulator or device.

---

## Dependencies
None — the app uses only:
- SwiftUI (built-in)
- SwiftData (built-in, iOS 17+)
- UserNotifications (built-in)
- URLSession for API calls (built-in)

No Swift Package Manager dependencies required.

---

## Architecture Notes

- **@Observable** macro used for ViewModels (iOS 17+)
- **SwiftData** for all persistence via `@Model` classes
- **ModelContext** injected via Environment throughout
- LLM API calls happen entirely on-device via user's own API key
- Google Books API used for search (onboarding) and enrichment (metadata)
- All data stored locally, no backend
