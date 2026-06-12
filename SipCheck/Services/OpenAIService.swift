import Foundation
import UIKit

/// Service for OpenAI API calls (Vision + Chat)
actor OpenAIService {
    static let shared = OpenAIService()

    /// When true, all API calls return fixed mock responses (no network)
    #if DEBUG
    static var useMockResponses = false
    #else
    static let useMockResponses: Bool = false
    #endif

    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"

    init() {
        self.apiKey = Config.openAIAPIKey
    }

    struct BeerExtractionResult {
        var name: String?
        var brand: String?
        var style: BeerStyle?
        var origin: String?
    }

    /// Extract beer information from an image using Vision API
    func extractBeerInfo(from image: UIImage) async throws -> BeerExtractionResult {
        if Self.useMockResponses {
            return BeerExtractionResult(name: "Mock IPA", brand: "Mock Brewery", style: .ipa, origin: "Mock Brewery was founded in 2005 in Portland, Oregon. They've been brewing bold IPAs ever since.")
        }

        guard !apiKey.isEmpty else {
            throw OpenAIError.noAPIKey
        }

        let resizedImage = resizeImage(image, maxDimension: 1024)

        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw OpenAIError.invalidImage
        }

        let base64Image = imageData.base64EncodedString()

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": """
                            Analyze this beer label image. Extract the following information:
                            1. Beer name
                            2. Brewery/Brand name
                            3. Beer style (choose from: IPA, Pale Ale, Lager, Pilsner, Stout, Porter, Wheat, Sour, Amber, Brown Ale, Belgian, Other)
                            4. A short origin story (1-2 sentences about the brewery's history or location — not flavor description)

                            Respond ONLY with a JSON object in this exact format:
                            {"name": "beer name", "brand": "brewery name", "style": "style from list", "origin": "short story or null"}

                            If you cannot determine a field, use null for that field.
                            """
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 300
        ]

        let responseData = try await makeRequest(endpoint: "/chat/completions", body: requestBody)
        return try parseExtractionResponse(responseData)
    }

    /// Get a personalized recommendation for a beer
    func getRecommendation(for beerName: String, existingDrink: Drink?, drinkHistory: [Drink]) async throws -> String {
        if Self.useMockResponses {
            if existingDrink != nil {
                return "Based on your preferences, this looks like a great choice! You enjoyed it before."
            } else {
                return "This could be a great pick based on your taste profile. Give it a try!"
            }
        }

        guard !apiKey.isEmpty else {
            throw OpenAIError.noAPIKey
        }

        // Build context about user's preferences
        var historyContext = "User's beer history:\n"
        let recentDrinks = drinkHistory.prefix(20)

        var likedStyles: [String: Int] = [:]
        var dislikedStyles: [String: Int] = [:]

        for drink in recentDrinks {
            historyContext += "- \(drink.name) (\(drink.style)): \(drink.rating.displayName)\n"

            switch drink.rating {
            case .like:
                likedStyles[drink.style, default: 0] += 1
            case .dislike:
                dislikedStyles[drink.style, default: 0] += 1
            case .neutral:
                break
            }
        }

        let tasteContext = TastePreferences.current.promptSummary

        let prompt: String
        if let existing = existingDrink {
            prompt = """
            \(tasteContext.isEmpty ? "" : "\(tasteContext)\n\n")The user is looking at "\(beerName)" which they have tried before.
            They rated it: \(existing.rating.displayName)
            \(existing.notes.map { "Their notes: \"\($0)\"" } ?? "")

            \(historyContext)

            Based on their rating and overall preferences, give a brief (2-3 sentences) personalized recommendation about whether they should order this beer again.
            Be conversational and helpful.
            """
        } else {
            prompt = """
            \(tasteContext.isEmpty ? "" : "\(tasteContext)\n\n")The user is considering "\(beerName)" which they have NOT tried before.

            \(historyContext)

            Liked styles: \(likedStyles.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
            Disliked styles: \(dislikedStyles.map { "\($0.key): \($0.value)" }.joined(separator: ", "))

            Based on their preferences, give a brief (2-3 sentences) personalized recommendation about whether this beer might be a good choice for them.
            Consider if this beer's likely style matches their preferences.
            Be conversational and helpful.
            """
        }

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "system",
                    "content": "You are a helpful beer recommendation assistant. Give brief, personalized recommendations based on the user's taste history. Be friendly and conversational."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 200
        ]

        let responseData = try await makeRequest(endpoint: "/chat/completions", body: requestBody)
        return try parseRecommendationResponse(responseData)
    }

    // MARK: - Private Methods

    private func makeRequest(endpoint: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: baseURL + endpoint) else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw OpenAIError.apiError(message)
            }
            throw OpenAIError.httpError(httpResponse.statusCode)
        }

        return data
    }

    private func parseExtractionResponse(_ data: Data) throws -> BeerExtractionResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.parseError
        }

        // Parse the JSON from the content
        guard let jsonStart = content.firstIndex(of: "{"),
              let jsonEnd = content.lastIndex(of: "}") else {
            throw OpenAIError.parseError
        }

        let jsonString = String(content[jsonStart...jsonEnd])
        guard let jsonData = jsonString.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any?] else {
            throw OpenAIError.parseError
        }

        var result = BeerExtractionResult()
        result.name = parsed["name"] as? String
        result.brand = parsed["brand"] as? String

        if let styleString = parsed["style"] as? String {
            result.style = BeerStyle.allCases.first { $0.rawValue.lowercased() == styleString.lowercased() }
        }

        result.origin = parsed["origin"] as? String

        return result
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    private func parseRecommendationResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.parseError
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum OpenAIError: LocalizedError {
    case noAPIKey
    case invalidImage
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not configured"
        case .invalidImage:
            return "Could not process image"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .parseError:
            return "Could not parse API response"
        }
    }
}
