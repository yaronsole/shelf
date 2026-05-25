import Foundation

// Single surface for all Cloud Run API calls.
// Auth token is injected from Keychain into every request.
// All methods are async/await. No URLSession calls anywhere else in the app.
final class APIClient {
    static let shared = APIClient()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    // Note: no .convertFromSnakeCase strategy — explicit CodingKeys on each DTO
    // handle snake_case ↔ camelCase mapping. The strategy is unreliable when
    // combined with custom CodingKeys.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    // MARK: - Recommendations

    func fetchRecommendations(force: Bool = false) async throws -> [RecommendationDTO] {
        var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent(APIConfig.Endpoints.recommendations),
            resolvingAgainstBaseURL: false
        )!
        if force {
            components.queryItems = [URLQueryItem(name: "force", value: "true")]
        }
        return try await get(url: components.url!)
    }

    // MARK: - Seed Books

    func submitSeedBook(title: String, author: String, coverURL: String, domain: Domain = .books) async throws {
        let url = APIConfig.baseURL.appendingPathComponent(APIConfig.Endpoints.seedBooks)
        let body = SeedBookRequest(title: title, author: author, coverURL: coverURL, domain: domain.rawValue)
        try await post(url: url, body: body)
    }

    func fetchSeedBooks(domain: Domain = .books) async throws -> [SeedBookDTO] {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent(APIConfig.Endpoints.seedBooks), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "domain", value: domain.rawValue)]
        return try await get(url: components.url!)
    }

    func deleteSeedBook(id: String, domain: Domain = .books) async throws {
        let url = APIConfig.baseURL
            .appendingPathComponent(APIConfig.Endpoints.seedBooks)
            .appendingPathComponent(id)
        try await delete(url: url)
    }

    // MARK: - Reactions

    func submitReaction(bookId: String, kind: ReactionKind, domain: Domain = .books) async throws {
        let url = APIConfig.baseURL.appendingPathComponent(APIConfig.Endpoints.reactions)
        let body = ReactionRequest(bookId: bookId, kind: kind, domain: domain.rawValue)
        try await post(url: url, body: body)
    }

    // MARK: - Seen Books

    func submitSeenBooks(bookIds: [String], domain: Domain = .books) async throws {
        guard !bookIds.isEmpty else { return }
        let url = APIConfig.baseURL.appendingPathComponent(APIConfig.Endpoints.seenBooks)
        let body = SeenBooksRequest(bookIds: bookIds, domain: domain.rawValue)
        try await post(url: url, body: body)
    }

    // MARK: - Chain Discovery Suggestions (onboarding Step 2)

    func fetchSuggestions(
        for seedBook: BookSearchResult,
        domain: Domain = .books,
        count: Int = 3,
        exclude: [String] = []
    ) async throws -> [SuggestionDTO] {
        let url = APIConfig.baseURL.appendingPathComponent(APIConfig.Endpoints.suggestions)
        let body = SuggestionsRequest(
            seedBookTitle: seedBook.title,
            seedBookAuthor: seedBook.author,
            domain: domain.rawValue,
            count: count,
            exclude: exclude
        )
        return try await postForResponse(url: url, body: body)
    }

    // MARK: - Debug

    func fetchDebugInfo() async throws -> DebugInfoDTO {
        let url = APIConfig.baseURL.appendingPathComponent(APIConfig.Endpoints.debugInfo)
        return try await get(url: url)
    }

    // MARK: - Curated Lists (Phase 6)

    func fetchListCatalog() async throws -> ListCatalogDTO {
        let url = APIConfig.baseURL.appendingPathComponent(APIConfig.Endpoints.lists)
        return try await get(url: url)
    }

    func fetchListDetail(slug: String) async throws -> ListDetailDTO {
        let url = APIConfig.baseURL
            .appendingPathComponent(APIConfig.Endpoints.lists)
            .appendingPathComponent(slug)
        return try await get(url: url)
    }

    func reactToListBook(
        slug: String,
        bookId: String,
        title: String,
        author: String,
        coverURL: String,
        kind: ListReactionKind,
        domain: Domain = .books
    ) async throws {
        let url = APIConfig.baseURL
            .appendingPathComponent(APIConfig.Endpoints.lists)
            .appendingPathComponent(slug)
            .appendingPathComponent("react")
        let body = ListReactionRequest(
            bookId: bookId,
            title: title,
            author: author,
            coverURL: coverURL,
            kind: kind,
            domain: domain.rawValue
        )
        try await post(url: url, body: body)
    }

    func deleteListReaction(slug: String, bookId: String, domain: Domain = .books) async throws {
        var components = URLComponents(
            url: APIConfig.baseURL
                .appendingPathComponent(APIConfig.Endpoints.lists)
                .appendingPathComponent(slug)
                .appendingPathComponent("react")
                .appendingPathComponent(bookId),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "domain", value: domain.rawValue)]
        try await delete(url: components.url!)
    }

    // MARK: - Private HTTP primitives

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(KeychainService.anonymousToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func get<T: Decodable>(url: URL) async throws -> T {
        let request = makeRequest(url: url, method: "GET")
        return try await perform(request)
    }

    private func post<B: Encodable>(url: URL, body: B) async throws {
        var request = makeRequest(url: url, method: "POST")
        request.httpBody = try encoder.encode(body)
        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    private func postForResponse<B: Encodable, T: Decodable>(url: URL, body: B) async throws -> T {
        var request = makeRequest(url: url, method: "POST")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func delete(url: URL) async throws {
        let request = makeRequest(url: url, method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        try validate(response: response)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200...299: return
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        default: throw APIError.serverError(http.statusCode)
        }
    }
}
