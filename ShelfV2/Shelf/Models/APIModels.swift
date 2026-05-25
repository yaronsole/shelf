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
    // v2.2 enrichment
    let contextTag: String
    let acclaim: String
    let nytBestseller: Bool
    let nytWeeksOnList: Int?
    let readingTimeMinutes: Int?
    let becauseOf: String  // Phase 2 attribution; empty when none

    enum CodingKeys: String, CodingKey {
        case id, title, author, blurb, genre, era, domain, awards, acclaim
        case coverURL = "cover_url"
        case isComfortZonePush = "is_comfort_zone_push"
        case batchId = "batch_id"
        case contextTag = "context_tag"
        case nytBestseller = "nyt_bestseller"
        case nytWeeksOnList = "nyt_weeks_on_list"
        case readingTimeMinutes = "reading_time_minutes"
        case becauseOf = "because_of"
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
        contextTag = (try? c.decode(String.self, forKey: .contextTag)) ?? ""
        acclaim = (try? c.decode(String.self, forKey: .acclaim)) ?? ""
        nytBestseller = (try? c.decode(Bool.self, forKey: .nytBestseller)) ?? false
        nytWeeksOnList = try? c.decodeIfPresent(Int.self, forKey: .nytWeeksOnList)
        readingTimeMinutes = try? c.decodeIfPresent(Int.self, forKey: .readingTimeMinutes)
        becauseOf = (try? c.decodeIfPresent(String.self, forKey: .becauseOf)) ?? ""
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
    let exclude: [String]

    enum CodingKeys: String, CodingKey {
        case domain, count, exclude
        case seedBookTitle = "seed_book_title"
        case seedBookAuthor = "seed_book_author"
    }
}

struct SuggestionDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let author: String
    let coverURL: String
    let blurb: String
    let genre: String
    let era: String
    let awards: [String]
    let contextTag: String
    let acclaim: String
    let nytBestseller: Bool
    let nytWeeksOnList: Int?
    let readingTimeMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, author, blurb, genre, era, awards, acclaim
        case coverURL = "cover_url"
        case contextTag = "context_tag"
        case nytBestseller = "nyt_bestseller"
        case nytWeeksOnList = "nyt_weeks_on_list"
        case readingTimeMinutes = "reading_time_minutes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decode(String.self, forKey: .author)
        coverURL = (try? c.decode(String.self, forKey: .coverURL)) ?? ""
        blurb = (try? c.decode(String.self, forKey: .blurb)) ?? ""
        genre = (try? c.decode(String.self, forKey: .genre)) ?? ""
        era = (try? c.decode(String.self, forKey: .era)) ?? ""
        awards = (try? c.decode([String].self, forKey: .awards)) ?? []
        contextTag = (try? c.decode(String.self, forKey: .contextTag)) ?? ""
        acclaim = (try? c.decode(String.self, forKey: .acclaim)) ?? ""
        nytBestseller = (try? c.decode(Bool.self, forKey: .nytBestseller)) ?? false
        nytWeeksOnList = try? c.decodeIfPresent(Int.self, forKey: .nytWeeksOnList)
        readingTimeMinutes = try? c.decodeIfPresent(Int.self, forKey: .readingTimeMinutes)
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

// MARK: - Curated Lists (Phase 6)

struct ListMetadataDTO: Decodable, Identifiable {
    let slug: String
    let title: String
    let subtitle: String
    let description: String
    let curator: String
    let bookCount: Int
    let lastUpdated: String
    let colorStart: String
    let colorEnd: String
    let sortOrder: Int

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, title, subtitle, description, curator
        case bookCount = "book_count"
        case lastUpdated = "last_updated"
        case colorStart = "color_start"
        case colorEnd = "color_end"
        case sortOrder = "sort_order"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        title = try c.decode(String.self, forKey: .title)
        subtitle = (try? c.decode(String.self, forKey: .subtitle)) ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        curator = (try? c.decode(String.self, forKey: .curator)) ?? ""
        bookCount = (try? c.decode(Int.self, forKey: .bookCount)) ?? 0
        lastUpdated = (try? c.decode(String.self, forKey: .lastUpdated)) ?? ""
        colorStart = (try? c.decode(String.self, forKey: .colorStart)) ?? "#534AB7"
        colorEnd = (try? c.decode(String.self, forKey: .colorEnd)) ?? "#7F77DD"
        sortOrder = (try? c.decode(Int.self, forKey: .sortOrder)) ?? 0
    }
}

struct ListCatalogDTO: Decodable {
    let lists: [ListMetadataDTO]
}

enum ListUserStatus: String, Codable {
    case read, saved, passed
}

struct ListBookDTO: Decodable, Identifiable {
    let bookId: String
    let title: String
    let author: String
    let year: Int?
    let coverURL: String
    let userStatus: ListUserStatus?

    var id: String { bookId }

    enum CodingKeys: String, CodingKey {
        case title, author, year
        case bookId = "book_id"
        case coverURL = "cover_url"
        case userStatus = "user_status"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookId = try c.decode(String.self, forKey: .bookId)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decode(String.self, forKey: .author)
        year = try? c.decodeIfPresent(Int.self, forKey: .year)
        coverURL = (try? c.decode(String.self, forKey: .coverURL)) ?? ""
        userStatus = try? c.decodeIfPresent(ListUserStatus.self, forKey: .userStatus)
    }
}

struct ListDetailDTO: Decodable {
    let slug: String
    let metadata: ListMetadataDTO
    let books: [ListBookDTO]
}

enum ListReactionKind: String, Encodable {
    case read, saved, passed
}

struct ListReactionRequest: Encodable {
    let bookId: String
    let title: String
    let author: String
    let coverURL: String
    let kind: ListReactionKind
    let domain: String

    enum CodingKeys: String, CodingKey {
        case title, author, kind, domain
        case bookId = "book_id"
        case coverURL = "cover_url"
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
