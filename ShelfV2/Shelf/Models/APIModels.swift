import Foundation

// MARK: - Request / Response DTOs for Cloud Run API

// MARK: Recommendation

struct RecommendationDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let author: String
    let coverURL: String
    let blurb: String
    let genre: String
    let era: String
    let isComfortZonePush: Bool
    let batchId: String
    let domain: String
    let awards: [String]
    let averageRating: Double?
    let ratingsCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, author, blurb, genre, era, domain, awards
        case coverURL = "cover_url"
        case isComfortZonePush = "is_comfort_zone_push"
        case batchId = "batch_id"
        case averageRating = "average_rating"
        case ratingsCount = "ratings_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decode(String.self, forKey: .author)
        coverURL = try c.decode(String.self, forKey: .coverURL)
        blurb = try c.decode(String.self, forKey: .blurb)
        genre = try c.decode(String.self, forKey: .genre)
        era = try c.decode(String.self, forKey: .era)
        isComfortZonePush = try c.decode(Bool.self, forKey: .isComfortZonePush)
        batchId = try c.decode(String.self, forKey: .batchId)
        domain = try c.decode(String.self, forKey: .domain)
        // Be lenient — older cached docs won't have these fields
        awards = (try? c.decode([String].self, forKey: .awards)) ?? []
        averageRating = try? c.decodeIfPresent(Double.self, forKey: .averageRating)
        ratingsCount = try? c.decodeIfPresent(Int.self, forKey: .ratingsCount)
    }
}

// MARK: Seed Book

struct SeedBookDTO: Codable, Identifiable {
    let id: String
    let title: String
    let author: String
    let coverURL: String
    let domain: String

    enum CodingKeys: String, CodingKey {
        case id, title, author, domain
        case coverURL = "cover_url"
    }
}

struct SeedBookRequest: Encodable {
    let title: String
    let author: String
    let coverURL: String
    let domain: String

    enum CodingKeys: String, CodingKey {
        case title, author, domain
        case coverURL = "cover_url"
    }
}

// MARK: Reaction

enum ReactionKind: String, Codable {
    case save = "save"
    case dismiss = "dismiss"
    case alreadyReadLiked = "alreadyReadLiked"
    case alreadyReadDisliked = "alreadyReadDisliked"
}

struct ReactionRequest: Encodable {
    let bookId: String
    let kind: ReactionKind
    let domain: String

    enum CodingKeys: String, CodingKey {
        case kind, domain
        case bookId = "book_id"
    }
}

// MARK: Seen Books

struct SeenBooksRequest: Encodable {
    let bookIds: [String]
    let domain: String

    enum CodingKeys: String, CodingKey {
        case domain
        case bookIds = "book_ids"
    }
}

// MARK: Chain Discovery (onboarding Step 2)

struct SuggestionsRequest: Encodable {
    let seedBookTitle: String
    let seedBookAuthor: String
    let domain: String
    let count: Int

    enum CodingKeys: String, CodingKey {
        case domain, count
        case seedBookTitle = "seed_book_title"
        case seedBookAuthor = "seed_book_author"
    }
}

struct SuggestionDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let author: String
    let coverURL: String

    enum CodingKeys: String, CodingKey {
        case id, title, author
        case coverURL = "cover_url"
    }
}

// MARK: Debug

struct DebugInfoDTO: Decodable {
    let lastGenerationTimestamp: Date?
    let lastBatchSize: Int?

    enum CodingKeys: String, CodingKey {
        case lastGenerationTimestamp = "last_generation_timestamp"
        case lastBatchSize = "last_batch_size"
    }
}

// MARK: - API Error

enum APIError: LocalizedError {
    case unauthorized
    case notFound
    case serverError(Int)
    case decodingError(Error)
    case networkError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Authentication failed."
        case .notFound: return "Resource not found."
        case .serverError(let code): return "Server error (\(code))."
        case .decodingError(let e): return "Response parsing failed: \(e.localizedDescription)"
        case .networkError(let e): return e.localizedDescription
        case .invalidResponse: return "Invalid server response."
        }
    }
}
