import SwiftUI
import SwiftData

/// Detail view for a curated list. 2-per-row grid of covers.
/// Tap = open the book detail sheet. Long press = save to Shelf.
struct ListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var vm: ListDetailViewModel
    @AppStorage("hasSeenListTooltip") private var hasSeenListTooltip = false
    @State private var showTooltip = false
    @State private var selectedBook: ListBookDTO?

    init(slug: String) {
        _vm = State(initialValue: ListDetailViewModel(slug: slug))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            ScrollView {
                if let detail = vm.detail {
                    VStack(alignment: .leading, spacing: 16) {
                        header(detail.metadata)
                        LazyVGrid(columns: columns, spacing: 16) {
                            // Phase 2 backstop: backend already filters cover-less books
                            // from lists; guard here too so none can slip through.
                            ForEach(detail.books.filter { BookCoverView.hasValidCover($0.coverURL) }) { book in
                                ListBookTile(
                                    book: book,
                                    status: vm.status(for: book.bookId),
                                    onTap: {
                                        selectedBook = book
                                    },
                                    onLongPress: {
                                        vm.toggleSave(book, modelContext: modelContext)
                                        // Only fire "added" toast when saving (not when unsaving)
                                        if vm.status(for: book.bookId) == .saved {
                                            ToastManager.shared.show(.savedToShelf)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                } else if vm.isLoading {
                    ProgressView().padding(.top, 80)
                } else if let errorMessage = vm.errorMessage {
                    EmptyStateView(
                        systemImage: "exclamationmark.icloud",
                        title: "Couldn't load list",
                        subtitle: errorMessage,
                        action: { vm.load() },
                        actionLabel: Strings.Common.retry
                    )
                    .padding(.top, 60)
                }
            }

            if showTooltip {
                TooltipOverlay {
                    showTooltip = false
                    hasSeenListTooltip = true
                }
                .transition(.opacity)
            }
        }
        .navigationTitle(vm.detail?.metadata.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.loadIfNeeded()
            if !hasSeenListTooltip {
                showTooltip = true
            }
        }
        .sheet(item: $selectedBook) { book in
            ListBookDetailSheet(
                book: book,
                listTitle: vm.detail?.metadata.title ?? "",
                onReadLoved: {
                    vm.markRead(book, liked: true, modelContext: modelContext)
                    ToastManager.shared.show(.reactedRead)
                },
                onReadDisliked: {
                    vm.markRead(book, liked: false, modelContext: modelContext)
                    ToastManager.shared.show(.reactedPass)
                },
                onSave: {
                    vm.toggleSave(book, modelContext: modelContext)
                    // Only fire "added" toast when saving (not when unsaving)
                    if vm.status(for: book.bookId) == .saved {
                        ToastManager.shared.show(.savedToShelf)
                    }
                },
                onBuy: {
                    if let url = AmazonLinkService.searchURL(
                        title: book.title, author: book.author
                    ) {
                        openURL(url)
                    }
                }
            )
        }
    }

    private func header(_ meta: ListMetadataDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meta.title)
                .font(.title.bold())
            if !meta.description.isEmpty {
                Text(meta.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Cover tile

private struct ListBookTile: View {
    let book: ListBookDTO
    let status: ListUserStatus?
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var saveBounce: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            BookCoverView(url: book.coverURL)
                .overlay(
                    Rectangle()
                        .fill(.black)
                        .opacity(status == .read ? 0.15 : 0)
                        .allowsHitTesting(false)
                )

            switch status {
            case .read:
                StatusBadge(systemImage: "checkmark", background: Color(red: 0.23, green: 0.43, blue: 0.07))
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            case .saved:
                StatusBadge(systemImage: "bookmark.fill", background: Color(red: 0.09, green: 0.37, blue: 0.65))
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            case .passed:
                StatusBadge(systemImage: "xmark", background: Color(.systemGray2))
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            case .none:
                EmptyView()
            }
        }
        .scaleEffect(saveBounce ? 1.05 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.light()
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            Haptics.medium()
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) { saveBounce = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { saveBounce = false }
            }
            onLongPress()
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: status)
    }
}

private struct StatusBadge: View {
    let systemImage: String
    let background: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(background))
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Book detail sheet

/// Presented when a cover is tapped. Mirrors the For You / Similar Books PDP
/// (BookDetailView): cover + metadata + description, three equal-weight pill
/// CTAs pinned to the bottom, and an inline "did you like it?" sentiment overlay.
/// The only difference from that PDP is the first CTA: instead of "pass" we
/// surface "amazon" (Buy on Amazon), since a curated-list book can't be passed.
private struct ListBookDetailSheet: View {
    let book: ListBookDTO
    let listTitle: String
    let onReadLoved: () -> Void
    let onReadDisliked: () -> Void
    let onSave: () -> Void
    let onBuy: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inSentimentMode = false

    private var contextLine: String {
        if let year = book.year {
            return listTitle.isEmpty ? "\(year)" : "\(listTitle) · \(year)"
        }
        return listTitle
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BookCoverView(url: book.coverURL, width: min(UIScreen.main.bounds.width * 0.45, 180))
                        .padding(.top, 24)

                    VStack(spacing: 4) {
                        Text(book.title)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                        Text(book.author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !contextLine.isEmpty {
                            Text(contextLine)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 16)

                    if !book.description.isEmpty {
                        Text(book.description)
                            .font(.subheadline)
                            .foregroundStyle(Color(.label))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 120)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: BookShareService.shareText(title: book.title, author: book.author)) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Color(.secondaryLabel))
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.secondaryLabel))
                            .font(.title3)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                primaryCtaBar
            }
            .overlay {
                // Centered modal overlay (no chained sheet → no white-screen race)
                if inSentimentMode {
                    sentimentOverlay
                        .transition(.opacity)
                        .zIndex(50)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: inSentimentMode)
        }
    }

    private var primaryCtaBar: some View {
        HStack(spacing: 6) {
            Button {
                Haptics.light()
                onBuy()
            } label: {
                PillLabel(iconName: "cart", iconColor: Color(hexString: "444444"),
                          label: "amazon", labelColor: Color(hexString: "444444"),
                          background: .white, hasBorder: true)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.medium()
                onSave()
                dismiss()
            } label: {
                PillLabel(iconName: "bookmark.fill", iconColor: .white,
                          label: "save", labelColor: .white,
                          background: Color(hex: 0x1A1A1A), hasBorder: false)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.light()
                withAnimation { inSentimentMode = true }
            } label: {
                PillLabel(iconName: "checkmark", iconColor: Color(hexString: "3B6D11"),
                          label: "read it", labelColor: Color(hexString: "444444"),
                          background: .white, hasBorder: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 24)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// Centered modal popup — rendered as an overlay (not a sheet) so it stacks
    /// cleanly over the detail sheet without the SwiftUI sheet-on-sheet race.
    private var sentimentOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { inSentimentMode = false }
                }

            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("did you like it?")
                        .font(.title3.bold())
                        .foregroundStyle(Color(.label))
                    Text(book.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                VStack(spacing: 10) {
                    Button {
                        Haptics.medium()
                        onReadLoved()
                        dismiss()
                    } label: {
                        Label("loved it", systemImage: "heart.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(hexString: "D04763"))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.light()
                        onReadDisliked()
                        dismiss()
                    } label: {
                        Label("not for me", systemImage: "hand.thumbsdown")
                            .font(.headline)
                            .foregroundStyle(Color(hexString: "444444"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color(hexString: "DDDDDD"), lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Pill button label (matches BookDetailView's CTA pills)

private struct PillLabel: View {
    let iconName: String
    let iconColor: Color
    let label: String
    let labelColor: Color
    let background: Color
    let hasBorder: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(labelColor)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(background)
                .overlay(
                    hasBorder
                    ? RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(hexString: "DDDDDD"), lineWidth: 0.5)
                    : nil
                )
        )
    }
}

// MARK: - First-run tooltip (liquid-glass, long-press hint only)

private struct TooltipOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dimmed backdrop catches taps so users can dismiss anywhere
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            // Liquid-glass card centered on screen
            VStack(spacing: 14) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.9))

                VStack(spacing: 6) {
                    Text("Long-press to save")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text("Add a book to your shelf without leaving the list.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("tap anywhere to dismiss")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 40)
        }
    }
}
