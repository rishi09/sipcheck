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
    var photoFileName: String?
    var abv: Double?

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
    }

    var rating: Rating {
        get { Rating.from(intValue: ratingValue) }
        set { ratingValue = newValue.intValue }
    }

    var drinkType: DrinkType {
        get { DrinkType.from(intValue: typeValue) }
        set { typeValue = newValue.intValue }
    }

    // MARK: - CodingKeys & Safe Decoder

    enum CodingKeys: String, CodingKey {
        case id, name, brand, style, ratingValue, typeValue, notes, dateAdded, photoFileName, abv
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Beer"
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "Other"
        ratingValue = try c.decodeIfPresent(Int.self, forKey: .ratingValue) ?? 1
        typeValue = try c.decodeIfPresent(Int.self, forKey: .typeValue) ?? 1
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        photoFileName = try c.decodeIfPresent(String.self, forKey: .photoFileName)
        abv = try c.decodeIfPresent(Double.self, forKey: .abv)
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
