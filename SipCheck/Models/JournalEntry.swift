import Foundation

/// Rich journal entry — created intentionally when user logs a beer they tried
struct JournalEntry: Identifiable, Codable, Equatable, HasModifiedDate {
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
    var lastModifiedLocal: Date

    enum CodingKeys: String, CodingKey {
        case id, beerName, brand, style, abv, rating, notes, photoFileName, dateLogged, dateTried, linkedScanId, lastModifiedLocal
    }

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
        self.lastModifiedLocal = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        beerName = try c.decode(String.self, forKey: .beerName)
        brand = (try? c.decode(String.self, forKey: .brand)) ?? ""
        style = (try? c.decode(String.self, forKey: .style)) ?? ""
        abv = try? c.decode(Double.self, forKey: .abv)
        let rawRating = (try? c.decode(Int.self, forKey: .rating)) ?? 3
        rating = min(max(rawRating, 1), 5)
        notes = try? c.decode(String.self, forKey: .notes)
        photoFileName = try? c.decode(String.self, forKey: .photoFileName)
        dateLogged = (try? c.decode(Date.self, forKey: .dateLogged)) ?? Date()
        dateTried = try? c.decode(Date.self, forKey: .dateTried)
        linkedScanId = try? c.decode(UUID.self, forKey: .linkedScanId)
        lastModifiedLocal = (try? c.decode(Date.self, forKey: .lastModifiedLocal)) ?? dateLogged
    }
}
