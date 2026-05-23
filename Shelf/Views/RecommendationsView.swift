import SwiftUI
import UIKit

// MARK: - RecommendationsView

struct RecommendationsView: View {
    // When provided, we're in demo mode and use this VM instead of the live one.
    var demoVM: DemoRecommendationsViewModel? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(MilestoneManager.self) private var milestones

    @State private var vm: RecommendationsViewModel?
    @State private var alreadyReadBook: Book?

    // First-reveal state
    @AppStorage("hasSeenFirstRecommendations") private var hasSeenFirst = false
    @State private var showConfetti = false
    @State private var showFirstRevealBanner = false

    // Staggered card entrance
    @State private var cardsAnimatedIn = false

    // MARK: - Computed bridges (reads from whichever VM is active)

    private var activeBooks: [Book]        { demoVM?.books         ?? vm?.books         ?? [] }
    private var activeIsLoading: Bool      { demoVM?.isLoading     ?? vm?.isLoading     ?? false }
    private var activeError: String?       { demoVM?.errorMessage  ?? vm?.errorMessage }
    private var activePendingFollowUps: [Purchase] { vm?.pendingFollowUps ?? [] }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "1C1C1E").ignoresSafeArea()

            // Confetti burst on first reveal
            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .zIndex(50)
                    .allowsHitTesting(false)
            }

            // Main content
            Group {
                if activeIsLoading {
                    ShelfLoadingView()
                        .transition(.opacity)
                } else if let error = activeError {
                    ContentUnavailableView(
                        "Something went wrong",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    .foregroundStyle(.white)
                } else if activeBooks.isEmpty {
                    ContentUnavailableView(
                        "No recommendations yet",
                        systemImage: "sparkles",
                        description: Text("Pull down to get your first batch")
                    )
                    .foregroundStyle(.white)
                } else {
                    feedScrollView
                }
            }
            .animation(.easeInOut(duration: 0.35), value: activeIsLoading)

            // First-reveal banner
            if showFirstRevealBanner {
                VStack {
                    HStack {
                        Spacer()
                        Text("✨ Your first picks are in")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color(hex: "2C2C2E"))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        Spacer()
                    }
                    .padding(.top, 56)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(60)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            if vm == nil {
                vm = RecommendationsViewModel(modelContext: modelContext)
            }
            loadIfNeeded()
        }
        .onChange(of: activeBooks) { _, newBooks in
            if !newBooks.isEmpty {
                animateCardsIn(firstTime: !hasSeenFirst)
                if !hasSeenFirst { hasSeenFirst = true }
            }
        }
        .sheet(item: $alreadyReadBook) { book in
            AlreadyReadSheet(book: book) { liked in
                handleAlreadyRead(book: book, liked: liked)
                alreadyReadBook = nil
            }
            .presentationDetents([.fraction(0.35)])
        }
        .sheet(isPresented: Binding(
            get: { demoVM?.showUnlockSheet ?? false },
            set: { demoVM?.showUnlockSheet = $0 }
        )) {
            APIKeyUnlockView()
                .presentationDetents([.large])
        }
    }

    // MARK: - Feed scroll view

    private var feedScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Follow-up banners (live mode only)
                ForEach(activePendingFollowUps, id: \.id) { purchase in
                    FollowUpBannerView(purchase: purchase) { response in
                        vm?.submitFollowUp(purchase: purchase, response: response)
                    } onDismiss: {
                        vm?.dismissFollowUp(purchase: purchase)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                // Book cards with staggered entrance
                ForEach(Array(activeBooks.enumerated()), id: \.element.id) { index, book in
                    BookCard(
                        book: book,
                        onThumbsUp:   { handleThumbsUp(book: book) },
                        onThumbsDown: { handleThumbsDown(book: book) },
                        onAlreadyRead: { alreadyReadBook = book },
                        onBought:    { Task { await handlePurchase(book: book) } },
                        onWishlist:  { handleWishlist(book: book) }
                    )
                    .opacity(cardsAnimatedIn ? 1 : 0)
                    .offset(y: cardsAnimatedIn ? 0 : 40)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(Double(index) * 0.08),
                        value: cardsAnimatedIn
                    )
                }

                // Bottom pull-to-refresh hint
                if !activeBooks.isEmpty {
                    Text("Pull down for more recommendations")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.vertical, 20)
                }
            }
            .padding()
        }
        .refreshable {
            cardsAnimatedIn = false
            await performRefresh()
        }
    }

    // MARK: - Load / Refresh

    private func loadIfNeeded() {
        if let demoVM { demoVM.loadIfNeeded() }
        else { vm?.loadIfNeeded() }
    }

    private func performRefresh() async {
        if let demoVM { await demoVM.refresh() }
        else { await vm?.refresh() }
    }

    // MARK: - Action handlers

    private func handleThumbsUp(book: Book) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let demoVM { demoVM.thumbsUp(book: book) } else { vm?.thumbsUp(book: book) }
        milestones.recordLike()
    }

    private func handleThumbsDown(book: Book) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let demoVM { demoVM.thumbsDown(book: book) } else { vm?.thumbsDown(book: book) }
        milestones.recordPass()
    }

    private func handleAlreadyRead(book: Book, liked: Bool) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let demoVM { demoVM.alreadyRead(book: book, liked: liked) }
        else { vm?.alreadyRead(book: book, liked: liked) }
        if liked { milestones.recordLike() } else { milestones.recordPass() }
    }

    private func handlePurchase(book: Book) async {
        if let demoVM { await demoVM.logPurchase(book: book) }
        else { await vm?.logPurchase(book: book) }
        milestones.recordReaction()
    }

    private func handleWishlist(book: Book) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        if let demoVM { demoVM.addToWishlist(book: book) } else { vm?.addToWishlist(book: book) }
        milestones.recordLike()
    }

    // MARK: - Animations

    private func animateCardsIn(firstTime: Bool) {
        if firstTime {
            showConfetti = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showFirstRevealBanner = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                cardsAnimatedIn = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showFirstRevealBanner = false
                    showConfetti = false
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                cardsAnimatedIn = true
            }
        }
    }
}

// MARK: - Book Card

struct BookCard: View {
    let book: Book
    let onThumbsUp: () -> Void
    let onThumbsDown: () -> Void
    let onAlreadyRead: () -> Void
    let onBought: () -> Void
    let onWishlist: () -> Void

    @State private var thumbsUpTapped = false
    @State private var savedToWishlist = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cover + title row
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: URL(string: book.coverURL ?? "")) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "book.closed")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.gray)
                            )
                    }
                }
                .frame(width: 70, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    if let url = book.amazonKindleURL {
                        Link(destination: url) {
                            Label("Buy on Kindle", systemImage: "cart")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // DC-06: Attribution pill — amber capsule above reasoning blurb
            if let attribution = book.attribution, !attribution.isEmpty {
                Text(attribution)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "D4AF37").opacity(0.15))
                    .foregroundStyle(Color(hex: "D4AF37"))
                    .clipShape(Capsule())
            }

            // Reasoning blurb
            if let blurb = book.reasoningBlurb {
                Text(blurb)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // DC-03: Award badges using shared AwardBadge component (REG-04)
            if let badges = book.awards, !badges.isEmpty {
                BadgeRow(badges: badges)
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Action bar — DC-01: "Save" renamed to "Shelve it"
            HStack(spacing: 0) {
                ActionButton(
                    icon: thumbsUpTapped ? "hand.thumbsup.fill" : "hand.thumbsup",
                    label: "Like",
                    color: thumbsUpTapped ? .green : .white.opacity(0.7)) {
                    thumbsUpTapped = true
                    onThumbsUp()
                }
                ActionButton(icon: "hand.thumbsdown", label: "Pass", color: .white.opacity(0.7)) {
                    onThumbsDown()
                }
                ActionButton(icon: "checkmark.circle", label: "Read", color: .white.opacity(0.7)) {
                    onAlreadyRead()
                }
                ActionButton(icon: "cart.badge.plus", label: "Bought", color: .white.opacity(0.7)) {
                    onBought()
                }
                // DC-01: Renamed from "Save" to "Shelve it"
                ActionButton(
                    icon: savedToWishlist ? "bookmark.fill" : "bookmark",
                    label: "Shelve it",
                    color: savedToWishlist ? Color(hex: "D4AF37") : .white.opacity(0.7)) {
                    savedToWishlist = true
                    onWishlist()
                }
            }
        }
        .padding()
        .background(Color(hex: "2C2C2E"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18))
                Text(label).font(.system(size: 10))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Already Read Sheet

struct AlreadyReadSheet: View {
    let book: Book
    let onResponse: (Bool) -> Void

    var body: some View {
        ZStack {
            Color(hex: "1C1C1E").ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Did you like it?")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("\"\(book.title)\"")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 16) {
                    Button { onResponse(true) } label: {
                        Label("Loved it", systemImage: "heart.fill")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.green).foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button { onResponse(false) } label: {
                        Label("Didn't like it", systemImage: "hand.thumbsdown.fill")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(hex: "2C2C2E")).foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
}

// MARK: - Follow-Up Banner

struct FollowUpBannerView: View {
    let purchase: Purchase
    let onResponse: (FollowUpResponse) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bell.fill").foregroundStyle(.orange)
                Text("Did you finish \"\(purchase.bookTitle)\"?")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").foregroundStyle(.white.opacity(0.5))
                }
            }
            HStack(spacing: 8) {
                ForEach([FollowUpResponse.lovedIt, .itWasFine, .didntFinish], id: \.self) { resp in
                    Button { onResponse(resp) } label: {
                        Text(resp.label)
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(resp.color.opacity(0.15))
                            .foregroundStyle(resp.color)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .background(Color(hex: "2C2C2E"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }
}

extension FollowUpResponse: Hashable {
    var label: String {
        switch self {
        case .lovedIt:     return "❤️ Loved it"
        case .itWasFine:   return "👍 It was fine"
        case .didntFinish: return "❌ Didn't finish"
        }
    }
    var color: Color {
        switch self {
        case .lovedIt:     return .green
        case .itWasFine:   return .blue
        case .didntFinish: return .red
        }
    }
}
