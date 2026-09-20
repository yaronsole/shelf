import Foundation

enum APIConfig {
    // Cloud Run deployment: shelf-api in shelf-488022 (us-central1)
    static let baseURL: URL = {
        let urlString = ProcessInfo.processInfo.environment["SHELF_API_BASE_URL"]
            ?? "https://shelf-api-q2fr45guva-uc.a.run.app"
        return URL(string: urlString)!
    }()

    enum Endpoints {
        static let recommendations = "/v1/recommendations"
        static let seedBooks = "/v1/seed-books"
        static let reactions = "/v1/reactions"
        static let seenBooks = "/v1/seen-books"
        static let suggestions = "/v1/onboarding/suggestions"
        static let debugInfo = "/v1/debug/generation-info"
        static let lists = "/v1/lists"
        static let userSettings = "/v1/user/settings"
        static let userData = "/v1/user/data"
        static let bookOverview = "/v1/book-overview"
    }
}
