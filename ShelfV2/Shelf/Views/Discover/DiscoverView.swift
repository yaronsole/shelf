import SwiftUI
import SwiftData

struct DiscoverView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState

    @Query(
        filter: #Predicate<CachedRecommendation> { !$0.isReacted && !$0.isSeen },
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
                ScrollView {
                    LazyVStack(spacing: 16) {
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
                                    // Mark seen when card scrolls above the viewport (REC-07)
                                    // onDisappear fires for both directions; we track the feed index
                                    // to detect upward scroll.
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
            .navigationTitle(Strings.Discover.tabTitle)
            .navigationBarTitleDisplayMode(.large)
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
        EmptyStateView(
            systemImage: "books.vertical",
            title: "No picks right now",
            subtitle: vm.errorMessage ?? Strings.Discover.noRecsAvailable,
            action: vm.errorMessage != nil ? { vm.refreshIfNeeded(modelContext: modelContext) } : nil,
            actionLabel: vm.errorMessage != nil ? Strings.Common.retry : nil
        )
        .padding(.top, 60)
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
