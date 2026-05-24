import Foundation

// Used only for onboarding book search. The backend handles all other metadata
// enrichment (covers, ISBNs) at generation time.
struct GoogleBooksService {
    static let shared = GoogleBooksService()
    private init() {}

    private let baseURL = "https://www.googleapis.com/books/v1/volumes"

    func search(query: String) async throws -> [BookSearchResult] {
        guard query.count >= 2 else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(baseURL)?q=\(encoded)&maxResults=10&printType=books&key=\(Secrets.googleBooksAPIKey)") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try parseResults(data)
    }

    // Precise lookup by title + author — used to hydrate the curated popular-books grid.
    func lookup(title: String, author: String) async -> BookSearchResult? {
        let query = "intitle:\"\(title)\" inauthor:\(author)"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(baseURL)?q=\(encoded)&maxResults=1&printType=books&key=\(Secrets.googleBooksAPIKey)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let first = (try? parseResults(data))?.first else { return nil }
        return first
    }

    private func parseResults(_ data: Data) throws -> [BookSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item -> BookSearchResult? in
            guard let volumeInfo = item["volumeInfo"] as? [String: Any],
                  let title = volumeInfo["title"] as? String,
                  let volumeId = item["id"] as? String else { return nil }
            let author = (volumeInfo["authors"] as? [String])?.first ?? "Unknown"
            let imageLinks = volumeInfo["imageLinks"] as? [String: Any]
            // Enforce HTTPS on cover URLs (Google Books returns http://)
            let coverURL = ((imageLinks?["thumbnail"] as? String)
                ?? (imageLinks?["smallThumbnail"] as? String))?
                .replacingOccurrences(of: "http://", with: "https://")
            return BookSearchResult(id: volumeId, title: title, author: author, coverURL: coverURL)
        }
    }
}
