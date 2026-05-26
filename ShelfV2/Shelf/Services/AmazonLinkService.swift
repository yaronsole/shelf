import Foundation

// Canonical Amazon search deeplink builder. Every Amazon URL in the app must
// go through this — never hand-build the URL at a call site (regression guard RG-01).
enum AmazonLinkService {
    static func searchURL(title: String, author: String) -> URL? {
        let query = "\(title) \(author)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.amazon.com/s?k=\(encoded)&i=stripbooks")
    }
}
