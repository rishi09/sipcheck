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
    var style: String?
    var abv: Double?
    var verdict: Verdict
    var explanation: String
    var timestamp: Date
    var wantToTry: Bool
    var linkedJournalId: UUID?
    var lastModifiedLocal: Date

    enum CodingKeys: String, CodingKey {
        case id, beerName, style, abv, verdict, explanation, timestamp, wantToTry, linkedJournalId, lastModifiedLocal
    }

    init(
        id: UUID = UUID(),
        beerName: String,
        style: String? = nil,
        abv: Double? = nil,
        verdict: Verdict = .yourCall,
        explanation: String = "",
        timestamp: Date = Date(),
        wantToTry: Bool = false,
        linkedJournalId: UUID? = nil
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
        self.lastModifiedLocal = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        beerName = try c.decode(String.self, forKey: .beerName)
        style = try? c.decode(String.self, forKey: .style)
        abv = try? c.decode(Double.self, forKey: .abv)
        verdict = (try? c.decode(Verdict.self, forKey: .verdict)) ?? .yourCall
        explanation = (try? c.decode(String.self, forKey: .explanation)) ?? ""
        timestamp = (try? c.decode(Date.self, forKey: .timestamp)) ?? Date()
        wantToTry = (try? c.decode(Bool.self, forKey: .wantToTry)) ?? false
        linkedJournalId = try? c.decode(UUID.self, forKey: .linkedJournalId)
        lastModifiedLocal = (try? c.decode(Date.self, forKey: .lastModifiedLocal)) ?? timestamp
    }
}
