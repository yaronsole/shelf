import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var vm = OnboardingViewModel()
    var onComplete: () -> Void

    var body: some View {
        NavigationStack {
            switch vm.currentStep {
            case .apiKey:
                APIKeySetupView(vm: vm)
            case .bookSearch:
                BookSearchOnboardingView(vm: vm, onComplete: {
                    vm.saveAndFinish(modelContext: modelContext)
                    onComplete()
                })
            case .done:
                EmptyView()
            }
        }
    }
}

// MARK: - Step 1: API Key

struct APIKeySetupView: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to Shelf")
                        .font(.largeTitle.bold())
                    Text("Your personal book recommendation engine that gets smarter with every book you read.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose your AI provider")
                        .font(.headline)
                    Picker("Provider", selection: $vm.selectedProvider) {
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.headline)
                    Text(vm.selectedProvider == .claude
                         ? "Enter your Anthropic API key. Get one at console.anthropic.com"
                         : "Enter your OpenAI API key. Get one at platform.openai.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("sk-...", text: $vm.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Text("Your API key is stored securely in the iOS Keychain and never leaves your device.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    vm.currentStep = .bookSearch
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(vm.canProceedFromAPIKey ? Color.accentColor : Color.gray.opacity(0.4))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!vm.canProceedFromAPIKey)
            }
            .padding(24)
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Step 2: Book Reactions (OB-02)

struct BookSearchOnboardingView: View {
    @Bindable var vm: OnboardingViewModel
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Rate Books You've Read")
                    .font(.title2.bold())
                Text("Search for books you know. Mark loved ones and ones that didn't land.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label("\(vm.likedBooks.count) loved", systemImage: "heart.fill")
                        .foregroundStyle(.green)
                    if !vm.dislikedBooks.isEmpty {
                        Label("\(vm.dislikedBooks.count) didn't like", systemImage: "hand.thumbsdown.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption.bold())
                if vm.likedBooks.count < 5 {
                    Text("Need \(5 - vm.likedBooks.count) more loved books to continue")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemBackground))

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search for a book...", text: $vm.searchQuery)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await vm.searchBooks() } }
                if vm.isSearching {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Results
            if vm.searchResults.isEmpty && !vm.isSearching {
                if vm.searchQuery.isEmpty {
                    ContentUnavailableView(
                        "Search for a book",
                        systemImage: "books.vertical",
                        description: Text("Type a title or author — then mark what you loved or didn't")
                    )
                } else {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term")
                    )
                }
            } else {
                List(vm.searchResults) { book in
                    OnboardingBookRow(
                        book: book,
                        currentReaction: vm.reaction(for: book),
                        onLoved: { vm.react(to: book, liked: true) },
                        onDidntLike: { vm.react(to: book, liked: false) },
                        onRemove: { vm.removeReaction(for: book) }
                    )
                }
                .listStyle(.plain)
            }

            Divider()
            Button {
                onComplete()
            } label: {
                Text(vm.canFinish ? "Start Discovering Books" : "Love at least 5 books to continue")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(vm.canFinish ? Color.accentColor : Color.gray.opacity(0.4))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!vm.canFinish)
            .padding()
        }
        .navigationBarHidden(true)
        .onChange(of: vm.searchQuery) { _, new in
            if new.isEmpty { vm.searchResults = [] }
        }
        .task(id: vm.searchQuery) {
            try? await Task.sleep(for: .milliseconds(400))
            await vm.searchBooks()
        }
    }
}

// MARK: - Onboarding Book Row (OB-02)

struct OnboardingBookRow: View {
    let book: Book
    let currentReaction: Bool?   // nil = no reaction, true = loved, false = didn't like
    let onLoved: () -> Void
    let onDidntLike: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: book.coverURL ?? "")) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(Image(systemName: "book").foregroundStyle(.gray))
            }
            .frame(width: 44, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // OB-02: "Loved it" / "Didn't like" CTAs
            HStack(spacing: 6) {
                // Loved it button
                Button {
                    if currentReaction == true { onRemove() } else { onLoved() }
                } label: {
                    Image(systemName: currentReaction == true ? "heart.fill" : "heart")
                        .font(.system(size: 20))
                        .foregroundStyle(currentReaction == true ? .green : .gray.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(currentReaction == true ? Color.green.opacity(0.12) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Didn't like button
                Button {
                    if currentReaction == false { onRemove() } else { onDidntLike() }
                } label: {
                    Image(systemName: currentReaction == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(.system(size: 18))
                        .foregroundStyle(currentReaction == false ? .secondary : .gray.opacity(0.4))
                        .frame(width: 36, height: 36)
                        .background(currentReaction == false ? Color.gray.opacity(0.12) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentReaction)
    }
}
