import Foundation

/// Verdict from AI scan — should the user try this beer?
enum Verdict: String, Codable, CaseIterable {
    case tryIt = "try_it"
    case skipIt = "skip_it"
    case yourCall = "your_call"
}

/// Lightweight scan result — created automatically when user scans a beer
struct Scan: Identifiable, Codable, Equatable, HasModifiedDate {
    let id: UUID
    var beerName: String
    /// Local scan metadata. Brand and photo are intentionally not written to
    /// the production CloudKit Scan schema yet; once the beer is logged, both
    /// flow into Drink/JournalEntry, whose schemas already support them.
    var brand: String?
    var style: String?
    var abv: Double?
    var photoFileName: String?
    var verdict: Verdict
    var explanation: String
    var timestamp: Date
    var wantToTry: Bool
    var linkedJournalId: UUID?
    var origin: String?
    var lastModifiedLocal: Date
    /// Soft-delete tombstone flag (kept hidden so the deletion syncs cross-device).
    var isDeleted: Bool = false

    init(
        id: UUID = UUID(),
        beerName: String,
        brand: String? = nil,
        style: String? = nil,
        abv: Double? = nil,
        photoFileName: String? = nil,
        verdict: Verdict = .yourCall,
        explanation: String = "",
        timestamp: Date = Date(),
        wantToTry: Bool = false,
        linkedJournalId: UUID? = nil,
        origin: String? = nil
    ) {
        self.id = id
        self.beerName = beerName
        self.brand = brand
        self.style = style
        self.abv = abv
        self.photoFileName = photoFileName
        self.verdict = verdict
        self.explanation = explanation
        self.timestamp = timestamp
        self.wantToTry = wantToTry
        self.linkedJournalId = linkedJournalId
        self.origin = origin
        self.lastModifiedLocal = Date()
        self.isDeleted = false
    }

    // MARK: - CodingKeys & Safe Decoder

    enum CodingKeys: String, CodingKey {
        case id, beerName, brand, style, abv, photoFileName, verdict, explanation, timestamp, wantToTry, linkedJournalId, origin, lastModifiedLocal, isDeleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        beerName = try c.decodeIfPresent(String.self, forKey: .beerName) ?? "Unknown Beer"
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        style = try c.decodeIfPresent(String.self, forKey: .style)
        abv = try c.decodeIfPresent(Double.self, forKey: .abv)
        photoFileName = try c.decodeIfPresent(String.self, forKey: .photoFileName)
        verdict = try c.decodeIfPresent(Verdict.self, forKey: .verdict) ?? .yourCall
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        wantToTry = try c.decodeIfPresent(Bool.self, forKey: .wantToTry) ?? false
        linkedJournalId = try c.decodeIfPresent(UUID.self, forKey: .linkedJournalId)
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
        lastModifiedLocal = try c.decodeIfPresent(Date.self, forKey: .lastModifiedLocal) ?? timestamp
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
}
