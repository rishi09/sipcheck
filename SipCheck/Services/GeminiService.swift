import Foundation

/// Error types for Gemini API calls
enum GeminiError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Gemini API key not configured"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "Gemini API error: \(message)"
        case .parseError:
            return "Could not parse Gemini API response"
        }
    }
}

/// Service for Google Gemini 2.0 Flash API calls
class GeminiService: LLMProvider {
    static let shared = GeminiService()

    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

    init() {
        self.apiKey = Config.geminiAPIKey
    }

    func extractBeerInfo(fromText labelText: String) async throws -> BeerInfo {
        if OpenAIService.useMockResponses {
            return BeerInfo(name: "Mock Lager", brand: "Mock Brewing Co", style: .lager, abv: 5.0, origin: "Mock Brewing Co started in a garage in 2010. They've been crafting session lagers ever since.")
        }

        guard !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        let prompt = """
        Analyze the following beer label text. Extract the following information:
        1. Beer name
        2. Brewery/Brand name
        3. Beer style (choose from: IPA, Pale Ale, Lager, Pilsner, Stout, Porter, Wheat, Sour, Amber, Brown Ale, Belgian, Other)
        4. ABV (alcohol by volume as a number, e.g. 5.5)
        5. A short origin story (1-2 sentences about the brewery's history or location — not flavor description)

        Label text:
        \(labelText)

        Respond ONLY with a JSON object in this exact format:
        {"name": "beer name", "brand": "brewery name", "style": "style from list", "abv": 5.5, "origin": "short story or null"}

        If you cannot determine a field, use null for that field.
        """

        let responseData = try await makeRequest(prompt: prompt)
        return try parseExtractionResponse(responseData)
    }

    func getRecommendation(prompt: String) async throws -> String {
        if OpenAIService.useMockResponses {
            return "This could be a great pick based on your taste profile. Give it a try!"
        }

        guard !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        let tasteContext = TastePreferences.current.promptSummary
        let fullPrompt = tasteContext.isEmpty ? prompt : "\(tasteContext)\n\n\(prompt)"

        let responseData = try await makeRequest(prompt: fullPrompt)
        return try parseTextResponse(responseData)
    }

    // MARK: - Private Methods

    private func makeRequest(prompt: String) async throws -> Data {
        guard var urlComponents = URLComponents(string: baseURL) else {
            throw GeminiError.invalidResponse
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = urlComponents.url else {
            throw GeminiError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw GeminiError.apiError(message)
            }
            throw GeminiError.httpError(httpResponse.statusCode)
        }

        return data
    }

    private func parseExtractionResponse(_ data: Data) throws -> BeerInfo {
        let text = try extractTextFromResponse(data)

        // Find JSON object in response text
        guard let jsonStart = text.firstIndex(of: "{"),
              let jsonEnd = text.lastIndex(of: "}") else {
            throw GeminiError.parseError
        }

        let jsonString = String(text[jsonStart...jsonEnd])
        guard let jsonData = jsonString.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any?] else {
            throw GeminiError.parseError
        }

        var result = BeerInfo()
        result.name = parsed["name"] as? String
        result.brand = parsed["brand"] as? String

        if let styleString = parsed["style"] as? String {
            result.style = BeerStyle.allCases.first { $0.rawValue.lowercased() == styleString.lowercased() }
        }

        if let abvNumber = parsed["abv"] as? Double {
            result.abv = abvNumber
        } else if let abvString = parsed["abv"] as? String, let abvValue = Double(abvString) {
            result.abv = abvValue
        }

        result.origin = parsed["origin"] as? String

        return result
    }

    private func parseTextResponse(_ data: Data) throws -> String {
        let text = try extractTextFromResponse(data)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractTextFromResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiError.parseError
        }
        return text
    }
}
