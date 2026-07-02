import Foundation

/// Configuration for the app
/// Create a file called "Secrets.swift" with your API key:
/// ```
/// enum Secrets {
///     static let openAIAPIKey = "your-key-here"
/// }
/// ```
enum Config {
    static var openAIAPIKey: String {
        return sanitized(Secrets.openAIAPIKey)
    }

    static var manusAPIKey: String {
        return sanitized(Secrets.manusAPIKey)
    }

    static var geminiAPIKey: String {
        return sanitized(Secrets.geminiAPIKey)
    }

    /// Placeholder values copied from Secrets.swift.example ("your-key-here")
    /// pass `!isEmpty` gates and put doomed network calls on the enrichment
    /// path. Treat anything that can't be a real key as absent.
    private static func sanitized(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = key.lowercased()
        guard key.count >= 20,
              !key.contains(" "),
              !lower.contains("your"),
              !lower.contains("replace"),
              !lower.contains("here") else { return "" }
        return key
    }
}
