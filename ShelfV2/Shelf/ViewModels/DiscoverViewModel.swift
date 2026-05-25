import Foundation

@Observable
@MainActor
final class DiscoverViewModel {
    var lists: [ListMetadataDTO] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil

    func loadIfNeeded() {
        guard lists.isEmpty else { return }
        load()
    }

    func load() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let catalog = try await APIClient.shared.fetchListCatalog()
                self.lists = catalog.lists
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
