import Foundation

struct Book: Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var author: String
    var asin: String?
    var isbn: String?
    var coverURL: String?
    var description: String?
    var reasoningBlurb: String?
    var attribution: String?   // DC-06: short "Because you liked X" phrase from LLM
    var awards: [String]?
    // Extended metadata (populated by GoogleBooksService or DemoData)
    var synopsis: String?
    var publicationYear: Int?
    var pageCount: Int?
    var averageRating: Double?

    // REG-01: NEVER use ISBN_10 as an ASIN. Prefer real ASIN (dp/ URL) when set
    // explicitly (e.g. DemoData); fall back to ISBN search, then title+author search.
    var amazonKindleURL: URL? {
        // Real ASIN — only set by DemoData, never sourced from ISBN_10 (REG-01)
        if let asin = asin,
           asin.count == 10,
           asin.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return URL(string: "https://www.amazon.com/dp/\(asin)")
        }
        // ISBN search
        if let isbn = isbn, !isbn.isEmpty {
            return URL(string: "https://www.amazon.com/s?k=\(isbn)&i=stripbooks")
        }
        // Title + author search fallback — always available
        let query = "\(title) \(author)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.amazon.com/s?k=\(query)&i=stripbooks")
    }

    // REG-01: Always true — we always resolve to at least a search URL
    var hasValidAmazonLink: Bool { true }
}
