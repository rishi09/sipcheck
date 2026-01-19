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
        // Try to load from Secrets.swift (gitignored)
        // If not available, return empty string
        #if DEBUG
        return Secrets.openAIAPIKey
        #else
        return ""
        #endif
    }
}
