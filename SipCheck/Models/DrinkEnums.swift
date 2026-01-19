import Foundation

/// Rating for a drink
enum Rating: String, CaseIterable {
    case like = "like"
    case neutral = "neutral"
    case dislike = "dislike"

    var emoji: String {
        switch self {
        case .like: return "👍"
        case .neutral: return "😐"
        case .dislike: return "👎"
        }
    }

    var displayName: String {
        switch self {
        case .like: return "Like"
        case .neutral: return "Neutral"
        case .dislike: return "Dislike"
        }
    }

    var intValue: Int {
        switch self {
        case .dislike: return 0
        case .neutral: return 1
        case .like: return 2
        }
    }

    static func from(intValue: Int) -> Rating {
        switch intValue {
        case 0: return .dislike
        case 2: return .like
        default: return .neutral
        }
    }
}

/// Category of drink (extensible for future)
enum DrinkCategory: String, CaseIterable {
    case beer = "beer"
    case cocktail = "cocktail"
    case wine = "wine"

    var displayName: String {
        switch self {
        case .beer: return "Beer"
        case .cocktail: return "Cocktail"
        case .wine: return "Wine"
        }
    }
}

/// Type of drink serving
enum DrinkType: String, CaseIterable {
    case draft = "draft"
    case regular = "regular"

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .regular: return "Bottle/Can"
        }
    }

    var intValue: Int {
        switch self {
        case .draft: return 0
        case .regular: return 1
        }
    }

    static func from(intValue: Int) -> DrinkType {
        switch intValue {
        case 0: return .draft
        default: return .regular
        }
    }
}

/// Beer styles for v1
enum BeerStyle: String, CaseIterable {
    case ipa = "IPA"
    case paleAle = "Pale Ale"
    case lager = "Lager"
    case pilsner = "Pilsner"
    case stout = "Stout"
    case porter = "Porter"
    case wheat = "Wheat"
    case sour = "Sour"
    case amber = "Amber"
    case brownAle = "Brown Ale"
    case belgian = "Belgian"
    case other = "Other"

    var displayName: String {
        return self.rawValue
    }
}
