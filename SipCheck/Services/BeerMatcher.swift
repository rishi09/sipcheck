import Foundation

/// Service for matching beers against local database
enum BeerMatcher {
    /// Find a matching drink in the user's history
    /// Uses fuzzy matching to handle variations in naming
    static func findMatch(for query: String, in drinks: [Drink]) -> Drink? {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return nil }
        let candidates = drinks.map { (drink: $0, name: normalize($0.name)) }

        // First, try exact match
        if let exact = candidates.first(where: { $0.name == normalizedQuery }) {
            return exact.drink
        }

        // Generic names ("IPA", "Ale") must not claim every beer of that
        // style. Among meaningful contains matches, choose the closest name
        // instead of whichever drink happened to be stored first.
        let containsMatches = candidates.compactMap { candidate -> (drink: Drink, similarity: Double)? in
            guard min(candidate.name.count, normalizedQuery.count) >= 5,
                  candidate.name.contains(normalizedQuery) || normalizedQuery.contains(candidate.name) else {
                return nil
            }
            return (candidate.drink, calculateSimilarity(candidate.name, normalizedQuery))
        }
        if let contains = containsMatches.max(by: { $0.similarity < $1.similarity }) {
            return contains.drink
        }

        // Try the BEST fuzzy match with Levenshtein distance. Returning the
        // first drink above threshold made storage order decide identity. A
        // long OCR page cannot reach the threshold against a short beer name,
        // so skip that wasted quadratic pass after containment has failed.
        guard normalizedQuery.count <= 160 else { return nil }
        let threshold = 0.7 // 70% similarity
        return candidates
            .map { (drink: $0.drink, similarity: calculateSimilarity($0.name, normalizedQuery)) }
            .filter { $0.similarity >= threshold }
            .max { $0.similarity < $1.similarity }?
            .drink
    }

    /// Strict variant for "you've had this one" claims: exact normalized-name
    /// equality only. The loose substring/fuzzy `findMatch` produces false
    /// banners ("Voodoo" ≠ "Voodoo Ranger Juice Force").
    static func exactMatch(for query: String, in drinks: [Drink]) -> Drink? {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return nil }
        return drinks.first { normalize($0.name) == normalizedQuery }
    }

    static func exactNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalize(lhs)
        return !left.isEmpty && left == normalize(rhs)
    }

    /// Normalize a string for comparison
    private static func normalize(_ string: String) -> String {
        let folded = string.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US")
        )
        let withoutApostrophes = folded.filter { $0 != "'" && $0 != "’" }
        return String(withoutApostrophes.map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Calculate similarity between two strings (0.0 to 1.0).
    /// Internal so `BundledCatalog` can reuse it for typo-tolerant catalog matching.
    static func calculateSimilarity(_ s1: String, _ s2: String) -> Double {
        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)
        guard maxLength > 0 else { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLength))
    }

    /// Levenshtein distance using two rolling rows (O(min(m,n)) memory).
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        var left = Array(s1)
        var right = Array(s2)
        if left.count < right.count { swap(&left, &right) }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        for (leftIndex, leftCharacter) in left.enumerated() {
            current[0] = leftIndex + 1
            for (rightIndex, rightCharacter) in right.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + substitutionCost
                )
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}
