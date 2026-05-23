import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DiscoverView()
                .tabItem {
                    Label(Strings.Discover.tabTitle, systemImage: "sparkles")
                }

            ReadingListView()
                .tabItem {
                    Label(Strings.ReadingList.tabTitle, systemImage: "bookmark")
                }

            TasteProfileView()
                .tabItem {
                    Label(Strings.TasteProfile.tabTitle, systemImage: Domain.books.tabIcon)
                }

            SettingsView()
                .tabItem {
                    Label(Strings.Settings.tabTitle, systemImage: "gear")
                }
        }
    }
}
