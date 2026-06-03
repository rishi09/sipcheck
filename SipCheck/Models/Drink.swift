import Foundation

/// Drink model - uses Codable for JSON persistence instead of SwiftData
struct Drink: Identifiable, Codable, Equatable, HasModifiedDate {
    var id: UUID = UUID()
    var name: String
    var brand: String
    var style: String
    var ratingValue: Int  // 0 = dislike, 1 = neutral, 2 = like
    var typeValue: Int    // 0 = draft, 1 = regular
    var notes: String?
    var dateAdded: Date
    var photoFileName: String?
    var abv: Double?
    var lastModifiedLocal: Date

    enum CodingKeys: String, CodingKey {
        case id, name, brand, style, ratingValue, typeValue, notes, dateAdded, photoFileName, abv, lastModifiedLocal
    }

    init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        style: String = "Other",
        rating: Rating = .neutral,
        type: DrinkType = .regular,
        notes: String? = nil,
        photoFileName: String? = nil,
        abv: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.style = style
        self.ratingValue = rating.intValue
        self.typeValue = type.intValue
        self.notes = notes
        self.dateAdded = Date()
        self.photoFileName = photoFileName
        self.abv = abv
        self.lastModifiedLocal = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        brand = (try? c.decode(String.self, forKey: .brand)) ?? ""
        style = (try? c.decode(String.self, forKey: .style)) ?? "Other"
        ratingValue = (try? c.decode(Int.self, forKey: .ratingValue)) ?? 1
        typeValue = (try? c.decode(Int.self, forKey: .typeValue)) ?? 1
        notes = try? c.decode(String.self, forKey: .notes)
        dateAdded = (try? c.decode(Date.self, forKey: .dateAdded)) ?? Date()
        photoFileName = try? c.decode(String.self, forKey: .photoFileName)
        abv = try? c.decode(Double.self, forKey: .abv)
        lastModifiedLocal = (try? c.decode(Date.self, forKey: .lastModifiedLocal)) ?? dateAdded
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
