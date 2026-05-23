import Foundation

enum APIConfig {
    // Replace with actual Cloud Run URL before shipping
    static let baseURL: URL = {
        let urlString = ProcessInfo.processInfo.environment["SHELF_API_BASE_URL"]
            ?? "https://shelf-api.example.com"
        return URL(string: urlString)!
    }()

    enum Endpoints {
        static let recommendations = "/v1/recommendations"
        static let seedBooks = "/v1/seed-books"
        static let reactions = "/v1/reactions"
        static let seenBooks = "/v1/seen-books"
        static let suggestions = "/v1/onboarding/suggestions"
        static let debugInfo = "/v1/debug/generation-info"
    }
}
