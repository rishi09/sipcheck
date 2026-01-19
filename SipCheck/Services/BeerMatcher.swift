import Foundation

/// Service for matching beers against local database
enum BeerMatcher {
    /// Find a matching drink in the user's history
    /// Uses fuzzy matching to handle variations in naming
    static func findMatch(for query: String, in drinks: [Drink]) -> Drink? {
        let normalizedQuery = normalize(query)

        // First, try exact match
        if let exact = drinks.first(where: { normalize($0.name) == normalizedQuery }) {
            return exact
        }

        // Try contains match
        if let contains = drinks.first(where: { normalize($0.name).contains(normalizedQuery) || normalizedQuery.contains(normalize($0.name)) }) {
            return contains
        }

        // Try fuzzy match with Levenshtein distance
        let threshold = 0.7 // 70% similarity
        for drink in drinks {
            let similarity = calculateSimilarity(normalize(drink.name), normalizedQuery)
            if similarity >= threshold {
                return drink
            }
        }

        return nil
    }

    /// Normalize a string for comparison
    private static func normalize(_ string: String) -> String {
        string
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  ", with: " ")
    }

    /// Calculate similarity between two strings (0.0 to 1.0)
    private static func calculateSimilarity(_ s1: String, _ s2: String) -> Double {
        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)
        guard maxLength > 0 else { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLength))
    }

    /// Levenshtein distance between two strings
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                if s1Array[i - 1] == s2Array[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = min(
                        matrix[i - 1][j] + 1,      // deletion
                        matrix[i][j - 1] + 1,      // insertion
                        matrix[i - 1][j - 1] + 1   // substitution
                    )
                }
            }
        }

        return matrix[m][n]
    }
}
