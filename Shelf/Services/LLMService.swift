import Foundation

enum LLMProvider: String, CaseIterable {
    case claude = "Claude (Anthropic)"
    case openAI = "GPT-4o (OpenAI)"
}

struct LLMRecommendation: Decodable {
    var title: String
    var author: String
    var reasoning: String
    // DC-03: 2-4 short genre/mood/format tags
    var badges: [String]?
    // DC-06: short attribution phrase, e.g. "Fans of Gone Girl" — max 6 words
    var attribution: String?
}

struct LLMService {
    static let shared = LLMService()
    private init() {}

    func getRecommendations(
        seeds: [SeedBook],
        thumbsUp: [Reaction],
        thumbsDown: [Reaction],
        alreadyReadLiked: [Reaction],
        alreadyReadDisliked: [Reaction],
        purchases: [Purchase],
        allShownTitles: [String],
        apiKey: String,
        provider: LLMProvider
    ) async throws -> [LLMRecommendation] {
        let prompt = buildPrompt(
            seeds: seeds,
            thumbsUp: thumbsUp,
            thumbsDown: thumbsDown,
            alreadyReadLiked: alreadyReadLiked,
            alreadyReadDisliked: alreadyReadDisliked,
            purchases: purchases,
            allShownTitles: allShownTitles
        )

        switch provider {
        case .claude:
            return try await callClaude(prompt: prompt, apiKey: apiKey)
        case .openAI:
            return try await callOpenAI(prompt: prompt, apiKey: apiKey)
        }
    }

    // MARK: - Prompt Builder

    private func buildPrompt(
        seeds: [SeedBook],
        thumbsUp: [Reaction],
        thumbsDown: [Reaction],
        alreadyReadLiked: [Reaction],
        alreadyReadDisliked: [Reaction],
        purchases: [Purchase],
        allShownTitles: [String]
    ) -> String {
        var lines: [String] = []

        lines.append("You are a personal book recommendation engine. Return ONLY a valid JSON array of up to 25 book recommendations.")
        lines.append("")
        lines.append("Each JSON object must have exactly these fields:")
        lines.append("  \"title\" (string): exact book title")
        lines.append("  \"author\" (string): exact author name")
        lines.append("  \"reasoning\" (string): see format below")
        lines.append("  \"badges\" (array of 2-4 strings): short tags — include at least one genre, one tone/mood, one format/structure badge. Examples: \"Literary fiction\", \"Slow burn\", \"Non-linear\", \"Debut novel\", \"Award winner\", \"Short chapters\"")
        lines.append("  \"attribution\" (string): a short phrase (max 6 words) naming the 1-2 books from the user's taste profile that most drove this pick. Format: \"Fans of [Book]\" or \"Like [Book] readers\". No 'Because'.")
        lines.append("")
        lines.append("## reasoning field — REQUIRED FORMAT (2-4 sentences, 60-100 words)")
        lines.append("Write like a well-read friend giving an honest hot take — specific to this book, connected to this user's actual taste.")
        lines.append("1. Name the specific book from their profile that makes this recommendation make sense (bold the title with **). Be plain: 'Fans of **X**...' or 'If **X** clicked for you...'. No phrases like 'given your fascination with' or 'your love of'.")
        lines.append("2. Describe what this book is actually about — specific and concrete. Name a character, a structural choice, a setting, or a key tension. No genre-speak or vague generalities.")
        lines.append("3. One honest quality: pacing, emotional register, writing style, or a structural detail that helps the user decide.")
        lines.append("BANNED words (never use): delve, journey, tapestry, poignant, harrowing, masterful, sweeping, tour de force, stunning, luminous, gripping, immersive, nuanced, visceral.")
        lines.append("Every blurb must feel grounded in THIS user's profile — no generic praise that could apply to any book.")
        lines.append("")

        // Positive seed books
        let positiveSeeds = seeds.filter { $0.isLiked }
        if !positiveSeeds.isEmpty {
            lines.append("## User's Seed Books (permanent taste anchor — weight heavily)")
            for book in positiveSeeds {
                lines.append("- \"\(book.title)\" by \(book.author)")
            }
        }

        // OB-02: Negative seed books — anti-signals equal weight to positive
        let negativeSeeds = seeds.filter { !$0.isLiked }
        if !negativeSeeds.isEmpty {
            lines.append("")
            lines.append("## Seed Books the user has read and disliked — AVOID similar books (equal weight to positive seeds)")
            for book in negativeSeeds {
                lines.append("- \"\(book.title)\" by \(book.author)")
            }
        }

        // Vibe-based seed titles from TasteSetupView
        if let vibeSeedTitles = UserDefaults.standard.stringArray(forKey: "seedBookTitles"),
           !vibeSeedTitles.isEmpty {
            if positiveSeeds.isEmpty {
                lines.append("")
                lines.append("## User's Taste Anchors (weight heavily)")
            }
            for title in vibeSeedTitles {
                lines.append("- \"\(title)\"")
            }
        }

        if !thumbsUp.isEmpty {
            lines.append("")
            lines.append("## Thumbs Up (positive signals)")
            for r in thumbsUp { lines.append("- \"\(r.bookTitle)\" by \(r.bookAuthor)") }
        }

        if !alreadyReadLiked.isEmpty {
            lines.append("")
            lines.append("## Already Read & Loved (strong positive signals)")
            for r in alreadyReadLiked { lines.append("- \"\(r.bookTitle)\" by \(r.bookAuthor)") }
        }

        let lovedPurchases = purchases.filter { $0.response == .lovedIt }
        let finePurchases  = purchases.filter { $0.response == .itWasFine }
        let dnfPurchases   = purchases.filter { $0.response == .didntFinish }

        if !lovedPurchases.isEmpty {
            lines.append("")
            lines.append("## Purchased & Loved (strongest positive signals)")
            for p in lovedPurchases { lines.append("- \"\(p.bookTitle)\" by \(p.bookAuthor)") }
        }

        if !finePurchases.isEmpty {
            lines.append("")
            lines.append("## Purchased & It Was Fine (mild positive signals)")
            for p in finePurchases { lines.append("- \"\(p.bookTitle)\" by \(p.bookAuthor)") }
        }

        if !thumbsDown.isEmpty || !alreadyReadDisliked.isEmpty || !dnfPurchases.isEmpty {
            lines.append("")
            lines.append("## Negative Signals — DO NOT recommend these or similar")
            for r in thumbsDown        { lines.append("- \"\(r.bookTitle)\" by \(r.bookAuthor) [thumbs down]") }
            for r in alreadyReadDisliked { lines.append("- \"\(r.bookTitle)\" by \(r.bookAuthor) [already read, disliked]") }
            for p in dnfPurchases      { lines.append("- \"\(p.bookTitle)\" by \(p.bookAuthor) [didn't finish]") }
        }

        // REG-06: Exclusion list is already capped at 100 by the caller (RecommendationsViewModel)
        if !allShownTitles.isEmpty {
            lines.append("")
            lines.append("## Already Shown — NEVER recommend these again")
            for title in allShownTitles { lines.append("- \(title)") }
        }

        lines.append("")
        lines.append("## Instructions")
        lines.append("- Seed books are the primary taste anchor, but always check the full reaction history for stronger or more specific signals.")
        lines.append("- The reasoning blurb must reference the strongest signal from the ENTIRE taste profile — seeds, thumbs-up, already read & loved, and purchased & loved.")
        lines.append("- Recommend real, published books only. Be specific and diverse within the user's taste.")
        lines.append("- Return ONLY the JSON array, no markdown fences, no preamble. Example format:")
        lines.append("[{\"title\": \"Book Title\", \"author\": \"Author Name\", \"reasoning\": \"If **Gone Girl** hit for you...\", \"badges\": [\"Psychological thriller\", \"Unreliable narrator\", \"Dual timeline\"], \"attribution\": \"Fans of Gone Girl\"}]")

        return lines.joined(separator: "\n")
    }

    // MARK: - Claude

    private func callClaude(prompt: String, apiKey: String) async throws -> [LLMRecommendation] {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = ((json?["content"] as? [[String: Any]])?.first)?["text"] as? String ?? ""
        return try parseRecommendations(from: content)
    }

    // MARK: - OpenAI

    private func callOpenAI(prompt: String, apiKey: String) async throws -> [LLMRecommendation] {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 4096
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = ((json?["choices"] as? [[String: Any]])?.first)?["message"] as? [String: Any]
        let text = content?["content"] as? String ?? ""
        return try parseRecommendations(from: text)
    }

    // MARK: - Parse

    private func parseRecommendations(from text: String) throws -> [LLMRecommendation] {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { throw URLError(.cannotParseResponse) }
        return try JSONDecoder().decode([LLMRecommendation].self, from: data)
    }
}
