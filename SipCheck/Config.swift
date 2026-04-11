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
        return Secrets.openAIAPIKey
    }

    static var manusAPIKey: String {
        return Secrets.manusAPIKey
    }

    static var geminiAPIKey: String {
        return Secrets.geminiAPIKey
    }
}
