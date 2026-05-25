import SwiftUI

struct ConfirmationView: View {
    @Bindable var vm: OnboardingViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    // Combine seed picks + added suggestions
    private var allBooks: [BookSearchResult] {
        var all = vm.selectedBooks
        for book in vm.selectedBooks {
            if let subs = vm.suggestions[book.id] {
                for s in subs where vm.addedSuggestions.contains(s.id) {
                    all.append(BookSearchResult(id: s.id, title: s.title, author: s.author, coverURL: s.coverURL))
                }
            }
        }
        return all
    }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    @State private var bookToRemove: BookSearchResult? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.Onboarding.Confirmation.title)
                    .font(.largeTitle.bold())
                Text(Strings.Onboarding.Confirmation.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Cover grid (OB-10)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(allBooks) { book in
                        ZStack(alignment: .topTrailing) {
                            BookCoverView(url: book.coverURL ?? "")
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                bookToRemove = book
                            } label: {
                                Label(Strings.Onboarding.Confirmation.removeAction, systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }

            // Submit CTA (OB-11)
            Button {
                vm.submitAndFinish(modelContext: modelContext, appState: appState)
            } label: {
                HStack(spacing: 8) {
                    if vm.isSubmitting {
                        ProgressView().controlSize(.small)
                            .tint(Color(.systemBackground))
                    }
                    Text(Strings.Onboarding.Confirmation.cta)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.label))
                .foregroundStyle(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(vm.isSubmitting)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.regularMaterial)
        }
        .confirmationDialog(
            Strings.Onboarding.Confirmation.removeWarning,
            isPresented: .constant(bookToRemove != nil),
            titleVisibility: .visible
        ) {
            Button(Strings.Onboarding.Confirmation.removeAction, role: .destructive) {
                if let book = bookToRemove {
                    vm.removeBook(book)
                    bookToRemove = nil
                }
            }
            Button(Strings.Onboarding.Confirmation.cancel, role: .cancel) {
                bookToRemove = nil
            }
        }
    }
}
