import Foundation

/// Drink model - uses Codable for JSON persistence instead of SwiftData
struct Drink: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var brand: String
    var style: String
    var ratingValue: Int  // 0 = dislike, 1 = neutral, 2 = like
    var typeValue: Int    // 0 = draft, 1 = regular
    var notes: String?
    var dateAdded: Date

    init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        style: String = "Other",
        rating: Rating = .neutral,
        type: DrinkType = .regular,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.style = style
        self.ratingValue = rating.intValue
        self.typeValue = type.intValue
        self.notes = notes
        self.dateAdded = Date()
    }

    var rating: Rating {
        get { Rating.from(intValue: ratingValue) }
        set { ratingValue = newValue.intValue }
    }

    var drinkType: DrinkType {
        get { DrinkType.from(intValue: typeValue) }
        set { typeValue = newValue.intValue }
    }

    static var preview: Drink {
        Drink(
            name: "Sierra Nevada Pale Ale",
            brand: "Sierra Nevada",
            style: "Pale Ale",
            rating: .like,
            notes: "Great hoppy flavor"
        )
    }
}
