import Foundation

/// Computed taste profile derived from a user's drink history
struct TasteProfile {
    var totalDrinks: Int = 0
    var likedCount: Int = 0
    var dislikedCount: Int = 0

    var favoriteStyles: [(style: String, count: Int)] = []
    var dislikedStyles: [(style: String, count: Int)] = []
    /// Mean ABV across ALL rated drinks — the honest "beers tried" statistic
    /// shown in Stats and prompt summaries.
    var averageABV: Double?
    /// Mean ABV across LIKED drinks only — the scorer's "ideal ABV" anchor.
    /// Averaging in the 9% stout the user hated would drag their sweet spot
    /// toward beers they avoid.
    var likedAverageABV: Double?

    /// Build a taste profile from drink history
    static func build(from drinks: [Drink]) -> TasteProfile {
        var profile = TasteProfile()
        profile.totalDrinks = drinks.count

        var likedStyleCounts: [String: Int] = [:]
        var dislikedStyleCounts: [String: Int] = [:]
        var abvSum: Double = 0
        var abvCount: Int = 0
        var likedABVSum: Double = 0
        var likedABVCount: Int = 0

        for drink in drinks {
            switch drink.rating {
            case .like:
                profile.likedCount += 1
                likedStyleCounts[drink.style, default: 0] += 1
                if let abv = drink.abv {
                    likedABVSum += abv
                    likedABVCount += 1
                }
            case .dislike:
                profile.dislikedCount += 1
                dislikedStyleCounts[drink.style, default: 0] += 1
            case .neutral:
                break
            }

            if let abv = drink.abv {
                abvSum += abv
                abvCount += 1
            }
        }

        profile.favoriteStyles = likedStyleCounts
            .sorted { $0.value > $1.value }
            .map { (style: $0.key, count: $0.value) }

        profile.dislikedStyles = dislikedStyleCounts
            .sorted { $0.value > $1.value }
            .map { (style: $0.key, count: $0.value) }

        if abvCount > 0 {
            profile.averageABV = abvSum / Double(abvCount)
        }
        if likedABVCount > 0 {
            profile.likedAverageABV = likedABVSum / Double(likedABVCount)
        }

        return profile
    }

    /// Generate a natural language summary for LLM context
    var promptSummary: String {
        var lines: [String] = []
        lines.append("Total beers tried: \(totalDrinks)")
        lines.append("Liked: \(likedCount), Disliked: \(dislikedCount)")

        if !favoriteStyles.isEmpty {
            let top = favoriteStyles.prefix(5).map { "\($0.style) (\($0.count))" }.joined(separator: ", ")
            lines.append("Favorite styles: \(top)")
        }

        if !dislikedStyles.isEmpty {
            let top = dislikedStyles.prefix(3).map { "\($0.style) (\($0.count))" }.joined(separator: ", ")
            lines.append("Disliked styles: \(top)")
        }

        if let avgABV = averageABV {
            lines.append("Average ABV of beers tried: \(String(format: "%.1f", avgABV))%")
        }

        return lines.joined(separator: "\n")
    }
}
