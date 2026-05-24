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
    // Returns the best of multiple results: filtering out junky editions (back-cover
    // scans, author-prefixed titles, results missing imageLinks).
    func lookup(title: String, author: String) async -> BookSearchResult? {
        let query = "intitle:\"\(title)\" inauthor:\(author)"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(baseURL)?q=\(encoded)&maxResults=10&printType=books&langRestrict=en&key=\(Secrets.googleBooksAPIKey)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let candidates = try? parseCandidates(data, expectedTitle: title, expectedAuthor: author) else { return nil }
        return candidates.first
    }

    private func parseResults(_ data: Data) throws -> [BookSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { Self.toResult($0) }
    }

    // Score-based candidate selection. Used by `lookup(title:author:)` so the popular-picks
    // grid avoids edition oddities like back-cover scans or "Author: Title" prefixed editions.
    private func parseCandidates(_ data: Data, expectedTitle: String, expectedAuthor: String) throws -> [BookSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }

        let normalizedExpected = expectedTitle.lowercased().trimmingCharacters(in: .whitespaces)

        let scored: [(score: Int, result: BookSearchResult)] = items.compactMap { item in
            guard let result = Self.toResult(item) else { return nil }
            guard let cover = result.coverURL, !cover.isEmpty else { return nil }
            let volumeInfo = item["volumeInfo"] as? [String: Any] ?? [:]
            var score = 0

            // Clean title: title without colon-prefix (e.g. "F. Scott Fitzgerald: The Great Gatsby"
            // ranks below "The Great Gatsby")
            let rawTitle = result.title.lowercased()
            if rawTitle == normalizedExpected { score += 100 }
            if rawTitle.hasPrefix(normalizedExpected) { score += 30 }
            if rawTitle.contains(":") && !normalizedExpected.contains(":") { score -= 25 }

            // Reward signals of a curated edition: categories, description, page count
            if (volumeInfo["categories"] as? [String])?.isEmpty == false { score += 20 }
            if let desc = volumeInfo["description"] as? String, desc.count > 100 { score += 15 }
            if let pages = volumeInfo["pageCount"] as? Int, pages >= 100 { score += 10 }

            // Penalize obviously junky publishers
            let publisher = (volumeInfo["publisher"] as? String ?? "").lowercased()
            let junkPublishers = ["createspace", "independently published", "lulu", "scholar select"]
            if junkPublishers.contains(where: publisher.contains) { score -= 40 }

            // Penalize covers that look like text-only artifacts. Google's thumbnails
            // for full cover art tend to have width >= 128; "stripped" covers are smaller.
            // We can't fully tell here, so use a weak signal: edge=curl typically means
            // a proper book cover scan with the curl effect.
            if cover.contains("edge=curl") { score += 5 }

            return (score, result)
        }

        return scored
            .sorted { $0.score > $1.score }
            .map(\.result)
    }

    private static func toResult(_ item: [String: Any]) -> BookSearchResult? {
        guard let volumeInfo = item["volumeInfo"] as? [String: Any],
              let title = volumeInfo["title"] as? String,
              let volumeId = item["id"] as? String else { return nil }
        let author = (volumeInfo["authors"] as? [String])?.first ?? "Unknown"
        let imageLinks = volumeInfo["imageLinks"] as? [String: Any]
        let coverURL = ((imageLinks?["thumbnail"] as? String)
            ?? (imageLinks?["smallThumbnail"] as? String))?
            .replacingOccurrences(of: "http://", with: "https://")
        return BookSearchResult(id: volumeId, title: title, author: author, coverURL: coverURL)
    }
}
