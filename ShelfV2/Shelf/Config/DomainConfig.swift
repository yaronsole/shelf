import Foundation

// Domain extensibility: all API calls and navigation use DomainConfig.
// Adding a new domain (recipes, restaurants) means adding a case here
// and a new tab in MainTabView — no other changes needed.
enum Domain: String, Codable, CaseIterable {
    case books = "books"
    // Future: case recipes = "recipes"
    // Future: case restaurants = "restaurants"

    var displayName: String {
        switch self {
        case .books: return "Books"
        }
    }

    var seedItemSingular: String {
        switch self {
        case .books: return "book"
        }
    }

    var seedItemPlural: String {
        switch self {
        case .books: return "books"
        }
    }

    var tabIcon: String {
        switch self {
        case .books: return "books.vertical"
        }
    }
}
