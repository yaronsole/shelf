import SwiftUI
import SwiftData

struct DiscoverView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState

    // Per PRD REC-07: seen books are excluded on the NEXT app open, not mid-session.
    // Pruning of seen books happens at launch in CoverBackfillService.pruneSeenItems;
    // here we only filter out books the user has reacted to.
    @Query(
        filter: #Predicate<CachedRecommendation> { !$0.isReacted },
        sort: \CachedRecommendation.fetchedAt,
        order: .reverse
    )
    private var feed: [CachedRecommendation]

    @State private var vm = DiscoverViewModel()

    // Tracks which card IDs have scrolled fully above the viewport
    @State private var visibleIds: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Sentinel for scroll-to-top after Load more
                            Color.clear.frame(height: 1).id("__top")

                            if appState.isFirstGeneration && feed.isEmpty {
                                firstGenerationEmptyState
                            } else if feed.isEmpty && !vm.isLoading {
                                noBooksEmptyState
                            } else {
                                ForEach(feed) { rec in
                                    BookCardView(
                                        rec: rec,
                                        onSave: { vm.save(rec, modelContext: modelContext) },
                                        onDismiss: { vm.dismiss(rec, modelContext: modelContext) },
                                        onAlreadyRead: { liked in vm.markAlreadyRead(rec, liked: liked, modelContext: modelContext) }
                                    )
                                    .padding(.horizontal, 16)
                                    .id(rec.id)
                                    .onDisappear {
                                        markSeenIfScrolledPast(rec)
                                    }
                                }

                                EndOfFeedView(
                                    taglineIndex: vm.currentTaglineIndex,
                                    isLoading: vm.isLoadingMore,
                                    onLoadMore: { vm.loadMore(modelContext: modelContext) }
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .refreshable {
                        await refreshAsync()
                    }
                    .onChange(of: vm.scrollToTopTick) { _, _ in
                        withAnimation(.easeOut(duration: 0.5)) {
                            scrollProxy.scrollTo("__top", anchor: .top)
                        }
                    }
                }

                // New batch banner (DISC-02)
                if vm.showNewBatchBanner {
                    newBatchBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }

                // Loading overlay on initial load only
                if vm.isLoading && feed.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                vm.refreshIfNeeded(modelContext: modelContext, isForegrounded: true)
            } else if phase == .background {
                vm.flushPendingSeen()
            }
        }
        .onAppear {
            vm.refreshIfNeeded(modelContext: modelContext)
        }
    }

    // MARK: - Empty States

    private var firstGenerationEmptyState: some View {
        EmptyStateView(
            systemImage: "sparkles",
            title: "Your shelf is being built",
            subtitle: Strings.Onboarding.Generating.copy
        )
        .padding(.top, 60)
    }

    private var noBooksEmptyState: some View {
        // Three distinct sub-cases:
        // 1. Network/decode error → "Try Again"
        // 2. Empty feed with no error → "Generate more" (user has reacted through them all)
        // 3. Default → "Generate more" too; tomorrow-morning copy is no longer accurate
        //    now that Load more / Generate more force fresh batches on demand.
        if vm.errorMessage != nil {
            return AnyView(
                EmptyStateView(
                    systemImage: "exclamationmark.icloud",
                    title: "No picks right now",
                    subtitle: vm.errorMessage ?? Strings.Discover.networkError,
                    action: { vm.refreshIfNeeded(modelContext: modelContext) },
                    actionLabel: Strings.Common.retry
                )
                .padding(.top, 60)
            )
        }
        return AnyView(
            EmptyStateView(
                systemImage: "books.vertical",
                title: "You're caught up",
                subtitle: "A fresh batch lands every morning at 3am.\nOr tap below to generate one now based on your latest reactions.",
                action: { vm.loadMore(modelContext: modelContext) },
                actionLabel: vm.isLoadingMore ? Strings.Common.loading : "Generate more"
            )
            .padding(.top, 60)
        )
    }

    // MARK: - New Batch Banner

    private var newBatchBanner: some View {
        HStack {
            Image(systemName: "sparkles")
            Text(Strings.Discover.newBatchBanner)
                .font(.subheadline.weight(.medium))
            Spacer()
            Button(Strings.Discover.refreshAction) {
                vm.dismissNewBatchBanner()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(radius: 6)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: - Seen Tracking

    // Uses the card's position in the feed array: if the card is no longer visible
    // and sits before still-visible cards, it has scrolled upward (REC-07).
    private func markSeenIfScrolledPast(_ rec: CachedRecommendation) {
        guard let idx = feed.firstIndex(where: { $0.id == rec.id }) else { return }
        let isBeforeAnyVisible = feed[idx...].dropFirst().contains { visibleIds.contains($0.id) }
            || (idx < feed.count - 1)
        if isBeforeAnyVisible {
            vm.markSeen(rec.id, modelContext: modelContext)
        }
    }

    private func refreshAsync() async {
        await withCheckedContinuation { continuation in
            Task {
                vm.refreshIfNeeded(modelContext: modelContext)
                try? await Task.sleep(for: .milliseconds(600))
                continuation.resume()
            }
        }
    }
}
