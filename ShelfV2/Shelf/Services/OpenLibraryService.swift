import Foundation

// Cover lookup via Open Library — much higher cover-art quality than Google Books.
// No API key required. Used by the Popular Picks grid and Taste-profile search to
// hydrate cover URLs for known title+author pairs.
struct OpenLibraryService {
    static let shared = OpenLibraryService()
    private init() {}

    private let searchURL = "https://openlibrary.org/search.json"

    /// Returns a high-resolution cover URL for the given title/author or nil.
    func lookupCoverURL(title: String, author: String) async -> String? {
        guard !title.isEmpty else { return nil }
        var components = URLComponents(string: searchURL)!
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "author", value: author),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "fields", value: "title,author_name,cover_i,first_publish_year,edition_count"),
            URLQueryItem(name: "sort", value: "editions"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("ShelfApp/2.0 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = json["docs"] as? [[String: Any]] else { return nil }
        for doc in docs {
            if let cid = doc["cover_i"] as? Int {
                return "https://covers.openlibrary.org/b/id/\(cid)-L.jpg"
            }
        }
        return nil
    }
}
