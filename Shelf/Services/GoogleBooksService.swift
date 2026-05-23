import Foundation

struct GoogleBooksService {
    static let shared = GoogleBooksService()
    private init() {}

    private let baseURL = "https://www.googleapis.com/books/v1/volumes"

    struct GoogleBooksResult {
        var coverURL: String?
        var isbn: String?
        var asin: String?
        var description: String?
    }

    // Search for books by query (used in onboarding)
    func search(query: String) async throws -> [Book] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(baseURL)?q=\(encoded)&maxResults=8&printType=books") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try parseVolumes(data)
    }

    // Enrich a book with metadata
    func enrich(title: String, author: String) async -> GoogleBooksResult {
        let query = "\(title) \(author)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "\(baseURL)?q=\(query)&maxResults=1&printType=books") else {
            return GoogleBooksResult()
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let books = try? parseVolumes(data),
              let first = books.first else {
            return GoogleBooksResult()
        }
        return GoogleBooksResult(
            coverURL: first.coverURL,
            isbn: first.isbn,
            asin: nil, // REG-01: never set asin from Google Books — ISBN_10 is not a valid ASIN
            description: first.description
        )
    }

    private func parseVolumes(_ data: Data) throws -> [Book] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item -> Book? in
            guard let volumeInfo = item["volumeInfo"] as? [String: Any],
                  let title = volumeInfo["title"] as? String else { return nil }
            let authors = (volumeInfo["authors"] as? [String])?.joined(separator: ", ") ?? "Unknown"
            let description = volumeInfo["description"] as? String
            let imageLinks = volumeInfo["imageLinks"] as? [String: Any]
            // Prefer the larger thumbnail; fall back to smallThumbnail
            var coverURL = (imageLinks?["thumbnail"] as? String)?
                .replacingOccurrences(of: "http://", with: "https://")
            if coverURL == nil {
                coverURL = (imageLinks?["smallThumbnail"] as? String)?
                    .replacingOccurrences(of: "http://", with: "https://")
            }
            // Extract ISBN from industryIdentifiers
            // REG-01: NEVER assign ISBN_10 to asin — ISBN_10 is not a valid Amazon ASIN
            var isbn: String?
            if let ids = volumeInfo["industryIdentifiers"] as? [[String: Any]] {
                for id in ids {
                    let type = id["type"] as? String ?? ""
                    let identifier = id["identifier"] as? String ?? ""
                    if type == "ISBN_13" { isbn = identifier }
                    if type == "ISBN_10" && isbn == nil { isbn = identifier }
                    // asin is intentionally NOT set here (REG-01)
                }
            }
            return Book(
                title: title,
                author: authors,
                asin: nil,   // REG-01: Google Books never provides real ASINs
                isbn: isbn,
                coverURL: coverURL,
                description: description
            )
        }
    }
}
