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
}
