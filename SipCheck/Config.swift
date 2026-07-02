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
    /// path. Structural checks only — no substring blocklists, which could
    /// silently reject a real key that happens to contain "here"/"your".
    private static let knownPlaceholders: Set<String> = [
        "your-key-here", "your-api-key-here", "your-key", "replace-me",
        "sk-your-key-here", "changeme"
    ]

    private static func sanitized(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 20,
              !key.contains(" "),
              !knownPlaceholders.contains(key.lowercased()) else { return "" }
        return key
    }
}
