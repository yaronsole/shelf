import SwiftUI

struct MainTabView: View {
    let isDemo: Bool

    @Environment(MilestoneManager.self) var milestones
    @State private var demoVM = DemoRecommendationsViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                RecommendationsView(demoVM: isDemo ? demoVM : nil)
                    .tabItem { Label("Discover", systemImage: "sparkles") }

                WishlistView()
                    .tabItem { Label("Wishlist", systemImage: "bookmark") }

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gear") }
            }

            // Milestone toast overlay
            if let toast = milestones.pendingToast {
                ToastView(message: toast.message) {
                    milestones.pendingToast = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: milestones.pendingToast?.id)
        .onAppear { checkReturnVisit() }
    }

    // MARK: - Return visit greeting

    private func checkReturnVisit() {
        let key = "lastOpenDate"
        let now = Date()

        if let last = UserDefaults.standard.object(forKey: key) as? Date {
            let days = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0
            if days >= 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        milestones.showReturnGreeting(daysSince: days)
                    }
                }
            }
        }

        UserDefaults.standard.set(now, forKey: key)
    }
}
