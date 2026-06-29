import Foundation

// Open Library service — no API key, no daily quota.
// Used for cover lookups (exact title/author) and free-text book search.
struct OpenLibraryService {
    static let shared = OpenLibraryService()
    private init() {}

    private let searchURL = "https://openlibrary.org/search.json"

    /// Free-text search — returns up to 10 results as BookSearchResult.
    /// Used in place of Google Books search (which has a 1000/day quota).
    func search(query: String) async -> [BookSearchResult] {
        guard query.count >= 2 else { return [] }
        // Genre-aware: a recognized genre term returns subject-filtered results
        // (Open Library subject search — no API quota). Falls through to the normal
        // title/author/keyword search when it's not a known genre or returns nothing.
        if let subject = Self.genreSubject(for: query) {
            let genreResults = await searchBySubject(subject)
            if !genreResults.isEmpty { return genreResults }
        }
        var components = URLComponents(string: searchURL)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "fields", value: "key,title,author_name,cover_i"),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("ShelfApp/2.0 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = json["docs"] as? [[String: Any]] else { return [] }
        return docs.compactMap { Self.parseDoc($0) }
    }

    // MARK: - Genre / subject search

    /// Open Library subject slug for a recognized free-text genre, else nil.
    /// Reliable for well-defined genres (graphic novels, sci-fi, fantasy…),
    /// looser for fuzzy ones (thriller); unmapped terms fall through to keyword
    /// search. Exact-match only, to avoid hijacking real title/author queries.
    static func genreSubject(for query: String) -> String? {
        genreMap[query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    private func searchBySubject(_ subject: String) async -> [BookSearchResult] {
        var components = URLComponents(string: searchURL)!
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "fields", value: "key,title,author_name,cover_i"),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("ShelfApp/2.0 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = json["docs"] as? [[String: Any]] else { return [] }
        return docs.compactMap { Self.parseDoc($0) }
    }

    private static func parseDoc(_ doc: [String: Any]) -> BookSearchResult? {
        guard let title = doc["title"] as? String else { return nil }
        let author = (doc["author_name"] as? [String])?.first ?? "Unknown"
        let key = (doc["key"] as? String) ?? "\(title)|\(author)"
        let coverURL: String? = (doc["cover_i"] as? Int).map {
            "https://covers.openlibrary.org/b/id/\($0)-M.jpg"
        }
        return BookSearchResult(id: key, title: title, author: author, coverURL: coverURL)
    }

    private static let genreMap: [String: String] = [
        "graphic novel": "graphic_novel", "graphic novels": "graphic_novel",
        "comic": "comics", "comics": "comics", "manga": "manga",
        "science fiction": "science_fiction", "sci-fi": "science_fiction",
        "scifi": "science_fiction", "sci fi": "science_fiction", "sf": "science_fiction",
        "fantasy": "fantasy", "mystery": "mystery", "mysteries": "mystery",
        "thriller": "thriller", "thrillers": "thriller", "suspense": "suspense",
        "romance": "romance", "romances": "romance", "horror": "horror",
        "young adult": "young_adult_fiction", "ya": "young_adult_fiction",
        "children's": "juvenile_fiction", "childrens": "juvenile_fiction",
        "children": "juvenile_fiction", "kids": "juvenile_fiction",
        "biography": "biography", "biographies": "biography",
        "memoir": "autobiography", "memoirs": "autobiography",
        "history": "history", "historical": "history",
        "historical fiction": "historical_fiction",
        "poetry": "poetry", "poems": "poetry",
        "self help": "self-help", "self-help": "self-help",
        "cookbook": "cooking", "cookbooks": "cooking", "cooking": "cooking",
        "philosophy": "philosophy", "psychology": "psychology",
        "crime": "crime", "true crime": "true_crime", "adventure": "adventure",
        "classics": "classic_literature", "classic": "classic_literature",
        "dystopia": "dystopian", "dystopian": "dystopian",
        "short stories": "short_stories",
        "humor": "humor", "humour": "humor", "comedy": "humor",
        "travel": "travel", "art": "art", "fiction": "fiction",
        "nonfiction": "nonfiction", "non-fiction": "nonfiction",
    ]

    /// Exact-match cover lookup for a known title+author pair.
    /// Sorts by edition count so the most-published (canonical) edition comes first.
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
        var request = URLRequest(url: url, timeoutInterval: 6)
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
