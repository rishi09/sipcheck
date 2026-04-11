import Foundation

/// Verdict from AI scan — should the user try this beer?
enum Verdict: String, Codable, CaseIterable {
    case tryIt = "try_it"
    case skipIt = "skip_it"
    case yourCall = "your_call"
}

/// Lightweight scan result — created automatically when user scans a beer
struct Scan: Identifiable, Codable, Equatable {
    let id: UUID
    var beerName: String
    var style: String?
    var abv: Double?
    var verdict: Verdict
    var explanation: String
    var timestamp: Date
    var wantToTry: Bool
    var linkedJournalId: UUID?
    var origin: String?

    init(
        id: UUID = UUID(),
        beerName: String,
        style: String? = nil,
        abv: Double? = nil,
        verdict: Verdict = .yourCall,
        explanation: String = "",
        timestamp: Date = Date(),
        wantToTry: Bool = false,
        linkedJournalId: UUID? = nil,
        origin: String? = nil
    ) {
        self.id = id
        self.beerName = beerName
        self.style = style
        self.abv = abv
        self.verdict = verdict
        self.explanation = explanation
        self.timestamp = timestamp
        self.wantToTry = wantToTry
        self.linkedJournalId = linkedJournalId
        self.origin = origin
    }

    // MARK: - CodingKeys & Safe Decoder

    enum CodingKeys: String, CodingKey {
        case id, beerName, style, abv, verdict, explanation, timestamp, wantToTry, linkedJournalId, origin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        beerName = try c.decodeIfPresent(String.self, forKey: .beerName) ?? "Unknown Beer"
        style = try c.decodeIfPresent(String.self, forKey: .style)
        abv = try c.decodeIfPresent(Double.self, forKey: .abv)
        verdict = try c.decodeIfPresent(Verdict.self, forKey: .verdict) ?? .yourCall
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        wantToTry = try c.decodeIfPresent(Bool.self, forKey: .wantToTry) ?? false
        linkedJournalId = try c.decodeIfPresent(UUID.self, forKey: .linkedJournalId)
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
    }
}
