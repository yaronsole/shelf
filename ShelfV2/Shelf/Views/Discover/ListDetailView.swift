import SwiftUI
import SwiftData

/// Detail view for a curated list. 2-per-row grid of covers.
/// Tap = open Amazon deeplink. Long press = save to Shelf.
struct ListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var vm: ListDetailViewModel
    @AppStorage("hasSeenListTooltip") private var hasSeenListTooltip = false
    @State private var showTooltip = false

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
                            ForEach(detail.books) { book in
                                ListBookTile(
                                    book: book,
                                    status: vm.status(for: book.bookId),
                                    onTap: {
                                        if let url = AmazonLinkService.searchURL(
                                            title: book.title, author: book.author
                                        ) {
                                            openURL(url)
                                        }
                                    },
                                    onLongPress: {
                                        vm.toggleSave(book)
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
    }

    private func header(_ meta: ListMetadataDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(meta.title)
                    .font(.title.bold())
                Spacer()
            }
            HStack(spacing: 6) {
                if !meta.curator.isEmpty {
                    Text(meta.curator).font(.subheadline.weight(.medium))
                    Text("·").foregroundStyle(.tertiary)
                }
                Text("\(meta.bookCount) books")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !meta.lastUpdated.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text("Updated \(meta.lastUpdated)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
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

// MARK: - First-run tooltip

private struct TooltipOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "hand.tap")
                    .font(.title)
                    .foregroundStyle(.white)
                Text("Tap to open on Amazon · Long-press to save")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text("Tap anywhere to dismiss")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.6)))
            .padding(.horizontal, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }
}
