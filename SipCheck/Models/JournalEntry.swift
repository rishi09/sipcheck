import Foundation

/// Rich journal entry — created intentionally when user logs a beer they tried
struct JournalEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var beerName: String
    var brand: String
    var style: String
    var abv: Double?
    var rating: Int  // 1-5 stars, clamped on set
    var notes: String?
    var photoFileName: String?
    var dateLogged: Date
    var dateTried: Date?
    var linkedScanId: UUID?

    init(
        id: UUID = UUID(),
        beerName: String,
        brand: String = "",
        style: String = "",
        abv: Double? = nil,
        rating: Int = 3,
        notes: String? = nil,
        photoFileName: String? = nil,
        dateLogged: Date = Date(),
        dateTried: Date? = nil,
        linkedScanId: UUID? = nil
    ) {
        self.id = id
        self.beerName = beerName
        self.brand = brand
        self.style = style
        self.abv = abv
        self.rating = min(max(rating, 1), 5)
        self.notes = notes
        self.photoFileName = photoFileName
        self.dateLogged = dateLogged
        self.dateTried = dateTried
        self.linkedScanId = linkedScanId
    }

    // MARK: - CodingKeys & Safe Decoder

    enum CodingKeys: String, CodingKey {
        case id, beerName, brand, style, abv, rating, notes, photoFileName, dateLogged, dateTried, linkedScanId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        beerName = try c.decodeIfPresent(String.self, forKey: .beerName) ?? "Unknown Beer"
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? ""
        abv = try c.decodeIfPresent(Double.self, forKey: .abv)
        rating = min(max(try c.decodeIfPresent(Int.self, forKey: .rating) ?? 3, 1), 5)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        photoFileName = try c.decodeIfPresent(String.self, forKey: .photoFileName)
        dateLogged = try c.decodeIfPresent(Date.self, forKey: .dateLogged) ?? Date()
        dateTried = try c.decodeIfPresent(Date.self, forKey: .dateTried)
        linkedScanId = try c.decodeIfPresent(UUID.self, forKey: .linkedScanId)
    }
}
