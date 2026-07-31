import Foundation

/// Remote artwork is reference media, never a captured photo. Keep it in a
/// separate field so Add Beer / Journal cannot accidentally upload a web image
/// as something the person photographed.
enum BeerReferenceImageURL {
    private static let blockedDomains = [
        "localhost", "local", "internal", "lan", "home", "onion", "test", "invalid", "example",
        // Public wildcard-DNS services can resolve an apparently public host
        // name to loopback/private space. Reference art never needs them.
        "nip.io", "sslip.io", "xip.io", "localtest.me", "localhost.direct", "lvh.me"
    ]

    static func validated(_ url: URL?) -> URL? {
        guard let url,
              url.absoluteString.utf8.count <= 2_048,
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(),
              !host.hasSuffix("."),
              host.contains("."),
              !host.contains(":"),
              !isIPv4Address(host),
              !isNumericHost(host),
              !blockedDomains.contains(where: { host == $0 || host.hasSuffix(".\($0)") }),
              host.split(separator: ".").allSatisfy({ label in
                  (1...63).contains(label.count)
                      && label.first != "-"
                      && label.last != "-"
                      && label.unicodeScalars.allSatisfy { scalar in
                          scalar.isASCII
                              && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
                      }
              }) else {
            return nil
        }
        return url
    }

    private static func isIPv4Address(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard let value = Int(part) else { return false }
            return (0...255).contains(value)
        }
    }

    private static func isNumericHost(_ host: String) -> Bool {
        host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            let value = label.lowercased()
            return !value.isEmpty && (value.allSatisfy(\.isNumber) || value.hasPrefix("0x"))
        }
    }
}

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
    /// Brand is encoded into the compatible CloudKit origin metadata field so
    /// strict saved/tried identity survives cross-device sync without a schema
    /// migration. Photos remain local until the beer is logged.
    var brand: String?
    var style: String?
    var abv: Double?
    var photoFileName: String?
    /// Exact product/reference image returned for an explicitly selected
    /// connected search result. This never enters the captured-photo pipeline.
    var referenceImageURL: URL?
    var verdict: Verdict
    var explanation: String
    var timestamp: Date
    var wantToTry: Bool
    var linkedJournalId: UUID?
    var origin: String?
    /// Exact page that grounded a selected search result. This is persisted in
    /// local JSON and encoded into the existing CloudKit origin string so older
    /// Production schemas retain source attribution without adding fields.
    var factSource: BeerFactSource?
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
        referenceImageURL: URL? = nil,
        verdict: Verdict = .yourCall,
        explanation: String = "",
        timestamp: Date = Date(),
        wantToTry: Bool = false,
        linkedJournalId: UUID? = nil,
        origin: String? = nil,
        factSource: BeerFactSource? = nil
    ) {
        self.id = id
        self.beerName = beerName
        self.brand = brand
        self.style = style
        self.abv = abv
        self.photoFileName = photoFileName
        self.referenceImageURL = BeerReferenceImageURL.validated(referenceImageURL)
        self.verdict = verdict
        self.explanation = explanation
        self.timestamp = timestamp
        self.wantToTry = wantToTry
        self.linkedJournalId = linkedJournalId
        self.origin = origin
        self.factSource = factSource
        self.lastModifiedLocal = Date()
        self.isDeleted = false
    }

    // MARK: - CodingKeys & Safe Decoder

    enum CodingKeys: String, CodingKey {
        case id, beerName, brand, style, abv, photoFileName, referenceImageURL, verdict, explanation, timestamp, wantToTry, linkedJournalId, origin, factSource, lastModifiedLocal, isDeleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        beerName = try c.decodeIfPresent(String.self, forKey: .beerName) ?? "Unknown Beer"
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        style = try c.decodeIfPresent(String.self, forKey: .style)
        abv = try c.decodeIfPresent(Double.self, forKey: .abv)
        photoFileName = try c.decodeIfPresent(String.self, forKey: .photoFileName)
        do {
            referenceImageURL = BeerReferenceImageURL.validated(
                try c.decodeIfPresent(URL.self, forKey: .referenceImageURL)
            )
        } catch {
            // Optional reference art must never make a person's scan history
            // unreadable after a corrupt or older payload.
            referenceImageURL = nil
        }
        verdict = try c.decodeIfPresent(Verdict.self, forKey: .verdict) ?? .yourCall
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        wantToTry = try c.decodeIfPresent(Bool.self, forKey: .wantToTry) ?? false
        linkedJournalId = try c.decodeIfPresent(UUID.self, forKey: .linkedJournalId)
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
        do {
            factSource = try c.decodeIfPresent(BeerFactSource.self, forKey: .factSource)
        } catch {
            // A malformed optional citation must not make the entire scan
            // history unreadable; discard only that untrusted link.
            factSource = nil
        }
        lastModifiedLocal = try c.decodeIfPresent(Date.self, forKey: .lastModifiedLocal) ?? timestamp
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
}
