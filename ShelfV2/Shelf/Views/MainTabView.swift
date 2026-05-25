import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ForYouView()
                .tabItem {
                    Label(Strings.ForYou.tabTitle, systemImage: "sparkles")
                }

            DiscoverView()
                .tabItem {
                    Label(Strings.Discover.tabTitle, systemImage: "square.grid.2x2")
                }

            ReadingListView()
                .tabItem {
                    Label(Strings.ReadingList.tabTitle, systemImage: "bookmark")
                }

            TasteProfileView()
                .tabItem {
                    Label(Strings.TasteProfile.tabTitle, systemImage: Domain.books.tabIcon)
                }
        }
    }
}
