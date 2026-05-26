import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0

    var body: some View {
        @Bindable var appState = appState
        ZStack {
            TabView(selection: $selectedTab) {
                ForYouView()
                    .tabItem {
                        Label(Strings.ForYou.tabTitle, systemImage: "sparkles")
                    }
                    .badge(appState.hasForYouBadge ? "·" : "")
                    .tag(0)

                DiscoverView()
                    .tabItem {
                        Label(Strings.Discover.tabTitle, systemImage: "square.grid.2x2")
                    }
                    .tag(1)

                ReadingListView()
                    .tabItem {
                        Label(Strings.ReadingList.tabTitle, systemImage: "bookmark")
                    }
                    .tag(2)

                TasteProfileView()
                    .tabItem {
                        Label(Strings.TasteProfile.tabTitle, systemImage: Domain.books.tabIcon)
                    }
                    .tag(3)
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == 0 {
                    appState.hasForYouBadge = false
                }
            }

            ToastOverlay()
        }
        .onAppear {
            if let tab = appState.pendingInitialTab {
                selectedTab = tab
                appState.pendingInitialTab = nil
                if appState.isFirstGeneration {
                    ToastManager.shared.show(.firstGeneration)
                }
            }
        }
    }
}
