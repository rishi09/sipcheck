import Foundation

/// Information extracted from a beer label
struct BeerInfo {
    var name: String?
    var brand: String?
    var style: BeerStyle?
    var abv: Double?
}

/// Protocol for LLM-based beer info extraction and recommendations
protocol LLMProvider {
    func extractBeerInfo(fromText labelText: String) async throws -> BeerInfo
    func getRecommendation(prompt: String) async throws -> String
}
