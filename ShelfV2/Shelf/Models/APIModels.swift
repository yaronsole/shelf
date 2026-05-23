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
}

// MARK: Seed Book

struct SeedBookDTO: Codable, Identifiable {
    let id: String
    let title: String
    let author: String
    let coverURL: String
    let domain: String
}

struct SeedBookRequest: Encodable {
    let title: String
    let author: String
    let coverURL: String
    let domain: String
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
}

// MARK: Seen Books

struct SeenBooksRequest: Encodable {
    let bookIds: [String]
    let domain: String
}

// MARK: Chain Discovery (onboarding Step 2)

struct SuggestionsRequest: Encodable {
    let seedBookTitle: String
    let seedBookAuthor: String
    let domain: String
    let count: Int
}

struct SuggestionDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let author: String
    let coverURL: String
}

// MARK: Debug

struct DebugInfoDTO: Decodable {
    let lastGenerationTimestamp: Date?
    let lastBatchSize: Int?
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
