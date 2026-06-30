import SwiftUI
import SwiftData

struct ForYouView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState

    @Query(
        filter: #Predicate<CachedRecommendation> { !$0.isReacted && $0.isSurfaced },
        sort: \CachedRecommendation.fetchedAt,
        order: .reverse
    )
    private var feed: [CachedRecommendation]

    // Staged "new picks" that arrived mid-session — held out of the feed until
    // the user taps the banner, so the feed never reshuffles under them.
    @Query(
        filter: #Predicate<CachedRecommendation> { !$0.isReacted && !$0.isSurfaced },
        sort: \CachedRecommendation.fetchedAt,
        order: .reverse
    )
    private var stagedRecs: [CachedRecommendation]

    @Query private var seedBooks: [LocalSeedBook]
    private let seedThreshold = 3

    @State private var vm = ForYouViewModel()
    @State private var visibleIds: Set<String> = []
    @State private var selectedRec: CachedRecommendation? = nil

    // Daily rotation — observe completion to fire TST-8
    private var rotationService = DailyRotationService.shared

    var body: some View {
        NavigationStack {
            if appState.forYouFeedUnlocked && seedBooks.count >= seedThreshold {
                feedBody
            } else {
                EmptyForYouView(onSeePicks: {
                    // User chose to graduate from the grid: kick off the first
                    // generation and switch to the personalized feed. Phase 5:
                    // first batch shows fast, then the feed fills in the background.
                    appState.isFirstGeneration = true
                    appState.unlockForYouFeed()
                    vm.generateFirstFeed(modelContext: modelContext)
                })
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                vm.refreshIfNeeded(modelContext: modelContext, isForegrounded: true)
                SimilarBooksCacheService.refreshAllIfNeeded(seeds: seedBooks, modelContext: modelContext)
                rotationService.triggerIfNeeded(modelContext: modelContext, seedCount: seedBooks.count)
            } else if phase == .background {
                vm.flushPendingSeen()
            }
        }
        .onChange(of: rotationService.rotationCompletedAt) { _, completedAt in
            guard let completedAt else { return }
            // Fire TST-8 only if For You is visible within 5 minutes of rotation
            if Date().timeIntervalSince(completedAt) < 300 {
                ToastManager.shared.show(.dailyRefresh)
            }
        }
        .onAppear {
            // Viewing the feed clears the "new recs" badge.
            appState.isViewingForYou = true
            appState.hasForYouBadge = false
            vm.refreshIfNeeded(modelContext: modelContext)
        }
        .onDisappear {
            appState.isViewingForYou = false
        }
        .onChange(of: vm.newBatchTick) { _, _ in
            // Light the badge only when fresh recs land while the user is NOT
            // looking at For You. If they're already on the feed, no badge —
            // that was the "badge shows all the time" bug.
            if !appState.isViewingForYou {
                appState.hasForYouBadge = true
            }
        }
        .sheet(item: $selectedRec) { rec in
            BookDetailView(
                rec: rec,
                onSave: {
                    vm.save(rec, modelContext: modelContext)
                    ToastManager.shared.show(.savedToShelf)
                },
                onPass: {
                    vm.dismiss(rec, modelContext: modelContext)
                    ToastManager.shared.show(.reactedPass)
                },
                onSentiment: { liked in
                    vm.markAlreadyRead(rec, liked: liked, modelContext: modelContext)
                    ToastManager.shared.show(liked ? .reactedRead : .reactedPass)
                }
            )
        }
    }

    private var feedBody: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        Color.clear.frame(height: 1).id("__top")

                        if appState.isFirstGeneration && feed.isEmpty && !vm.didReceiveFirstBatch {
                            firstGenerationEmptyState
                        } else if feed.isEmpty && !vm.isLoading {
                            noBooksEmptyState
                        } else {
                            ForEach(feed) { rec in
                                BookCardView(
                                    rec: rec,
                                    onTap: { selectedRec = rec },
                                    onSave: {
                                        vm.save(rec, modelContext: modelContext)
                                        ToastManager.shared.show(.savedToShelf)
                                    }
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
                .refreshable { await refreshAsync() }
                .onChange(of: vm.scrollToTopTick) { _, _ in
                    withAnimation(.easeOut(duration: 0.5)) {
                        scrollProxy.scrollTo("__top", anchor: .top)
                    }
                }
            }

            if !stagedRecs.isEmpty {
                newPicksBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }

            if vm.isLoading && feed.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Curating your picks…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("This can take up to a minute the first time.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        if vm.errorMessage != nil {
            return AnyView(
                EmptyStateView(
                    systemImage: "exclamationmark.icloud",
                    title: "No picks right now",
                    subtitle: vm.errorMessage ?? Strings.ForYou.networkError,
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

    private var newPicksBanner: some View {
        Button {
            Haptics.light()
            vm.surfaceStaged(modelContext: modelContext)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                Text("\(stagedRecs.count) new pick\(stagedRecs.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .shadow(radius: 6)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: - Seen Tracking

    private func markSeenIfScrolledPast(_ rec: CachedRecommendation) {
        guard let idx = feed.firstIndex(where: { $0.id == rec.id }) else { return }
        let isBeforeAnyVisible = feed[idx...].dropFirst().contains { visibleIds.contains($0.id) }
            || (idx < feed.count - 1)
        if isBeforeAnyVisible {
            vm.markSeen(rec.id, modelContext: modelContext)
        }
    }

    private func refreshAsync() async {
        vm.surfaceStaged(modelContext: modelContext)   // pull-to-refresh brings staged picks into the feed
        await withCheckedContinuation { continuation in
            Task {
                vm.refreshIfNeeded(modelContext: modelContext)
                try? await Task.sleep(for: .milliseconds(600))
                continuation.resume()
            }
        }
    }
}
