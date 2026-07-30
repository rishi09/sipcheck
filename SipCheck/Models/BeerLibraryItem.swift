import Foundation

/// Strict product identity used by the read-only beer-library projection.
///
/// Identity is deliberately conservative: a normalized name is paired with a
/// normalized brewery, and an unknown brewery only matches another unknown
/// brewery. Fuzzy catalog matching is useful for discovery, but is never safe
/// evidence for a past-tense personal claim.
struct BeerLibraryIdentity: Hashable {
    let normalizedName: String
    let normalizedBrewery: String
    private let placeholderRecordID: UUID?

    init(name: String, brewery: String?, recordID: UUID) {
        normalizedName = BeerMatcher.normalizedIdentityComponent(name)
        normalizedBrewery = BeerMatcher.normalizedIdentityComponent(brewery ?? "")
        placeholderRecordID = Self.isPlaceholder(normalizedName) ? recordID : nil
    }

    var isLookupEligible: Bool {
        !Self.isPlaceholder(normalizedName)
    }

    var stableSortKey: String {
        "\(normalizedName)|\(normalizedBrewery)|\(placeholderRecordID?.uuidString ?? "")"
    }

    static func strictlyMatches(
        name: String,
        brewery: String?,
        otherName: String,
        otherBrewery: String?
    ) -> Bool {
        let leftName = BeerMatcher.normalizedIdentityComponent(name)
        let rightName = BeerMatcher.normalizedIdentityComponent(otherName)
        guard !isPlaceholder(leftName), leftName == rightName else { return false }
        return BeerMatcher.normalizedIdentityComponent(brewery ?? "")
            == BeerMatcher.normalizedIdentityComponent(otherBrewery ?? "")
    }

    /// Used only for reconciling the two legacy persistence schemas. Unlike a
    /// personal-history lookup, this permits placeholder names because a close
    /// timestamp/photo can still prove that the records are one mirrored write.
    static func hasSameNormalizedTuple(
        name: String,
        brewery: String?,
        otherName: String,
        otherBrewery: String?
    ) -> Bool {
        BeerMatcher.normalizedIdentityComponent(name)
            == BeerMatcher.normalizedIdentityComponent(otherName)
            && BeerMatcher.normalizedIdentityComponent(brewery ?? "")
            == BeerMatcher.normalizedIdentityComponent(otherBrewery ?? "")
    }

    /// Explicit scan↔journal IDs carry more trust than a text lookup. Require
    /// the same non-placeholder name; when both sides know a brewery, require
    /// that too. This tolerates the legacy CloudKit Scan schema dropping brand
    /// while rejecting a link retained after the user changed the beer name.
    static func explicitLinkMatches(
        scanName: String,
        scanBrewery: String?,
        journalName: String,
        journalBrewery: String?
    ) -> Bool {
        let leftName = BeerMatcher.normalizedIdentityComponent(scanName)
        let rightName = BeerMatcher.normalizedIdentityComponent(journalName)
        guard !isPlaceholder(leftName), leftName == rightName else { return false }

        let leftBrewery = BeerMatcher.normalizedIdentityComponent(scanBrewery ?? "")
        let rightBrewery = BeerMatcher.normalizedIdentityComponent(journalBrewery ?? "")
        return leftBrewery.isEmpty || rightBrewery.isEmpty || leftBrewery == rightBrewery
    }

    private static func isPlaceholder(_ name: String) -> Bool {
        name.isEmpty || name == "unknown beer"
    }
}

/// One explicit taste observation. Journal values are authoritative for a
/// reconciled mirror; non-conflicting legacy-only metadata can fill gaps.
struct BeerTasteRecord: Identifiable {
    enum Source: String {
        case journal
        case legacyDrink
    }

    let id: UUID
    let name: String
    let brewery: String
    let style: String
    let abv: Double?
    let rating: Rating
    let stars: Int?
    let notes: String?
    let photoFileName: String?
    let date: Date
    let modifiedAt: Date
    let drinkType: DrinkType?
    let source: Source

    init(journalEntry: JournalEntry, pairedDrink: Drink? = nil) {
        id = journalEntry.id
        name = journalEntry.beerName
        brewery = journalEntry.brand
        style = journalEntry.style.isEmpty ? pairedDrink?.style ?? "" : journalEntry.style
        abv = journalEntry.abv ?? pairedDrink?.abv
        rating = Rating.from(stars: journalEntry.rating)
        stars = journalEntry.rating
        notes = journalEntry.notes
        photoFileName = journalEntry.photoFileName ?? pairedDrink?.photoFileName
        date = journalEntry.dateTried ?? journalEntry.dateLogged
        modifiedAt = journalEntry.lastModifiedLocal
        drinkType = pairedDrink?.drinkType
        source = .journal
    }

    init(legacyDrink: Drink) {
        id = legacyDrink.id
        name = legacyDrink.name
        brewery = legacyDrink.brand
        style = legacyDrink.style
        abv = legacyDrink.abv
        rating = legacyDrink.rating
        stars = nil
        notes = legacyDrink.notes
        photoFileName = legacyDrink.photoFileName
        date = legacyDrink.dateAdded
        modifiedAt = legacyDrink.lastModifiedLocal
        drinkType = legacyDrink.drinkType
        source = .legacyDrink
    }
}

extension Rating {
    /// One mapping for every Journal-to-taste conversion in the app.
    static func from(stars: Int) -> Rating {
        switch stars {
        case 4...: return .like
        case ...2: return .dislike
        default: return .neutral
        }
    }
}

/// A unique beer plus its surviving encounters and optional saved intent.
/// This type is derived in memory and is never persisted as a fourth store.
struct BeerLibraryItem: Identifiable {
    let id: BeerLibraryIdentity
    let journalEntries: [JournalEntry]
    let encounters: [BeerTasteRecord]
    let savedScans: [Scan]

    var latestEncounter: BeerTasteRecord? { encounters.first }
    var latestRating: Rating? { latestEncounter?.rating }
    var isTried: Bool { !encounters.isEmpty }
    var isSaved: Bool { !isTried && !savedScans.isEmpty }

    var name: String {
        firstNonempty(encounters.map(\.name))
            ?? firstNonempty(savedScans.map(\.beerName))
            ?? "Unknown Beer"
    }

    var brewery: String? {
        firstNonempty(encounters.map(\.brewery))
            ?? firstNonempty(savedScans.compactMap(\.brand))
    }

    var style: String? {
        firstNonempty(encounters.map(\.style))
            ?? firstNonempty(savedScans.compactMap(\.style))
    }

    var abv: Double? {
        encounters.compactMap(\.abv).first ?? savedScans.compactMap(\.abv).first
    }

    var photoFileName: String? {
        firstNonempty(encounters.compactMap(\.photoFileName))
            ?? firstNonempty(savedScans.compactMap(\.photoFileName))
    }

    var latestActivityDate: Date {
        max(
            latestEncounter?.date ?? .distantPast,
            savedScans.first?.timestamp ?? .distantPast
        )
    }

    private func firstNonempty(_ values: [String]) -> String? {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// One reliable read model over legacy Drinks, Journal encounters, and saved
/// scans. Journal records are the authority for one conservatively paired
/// mirror, including tombstones. Other encounters with the same beer identity
/// remain independent evidence.
struct BeerLibrarySnapshot {
    let items: [BeerLibraryItem]

    init(
        journalRecords: [JournalEntry],
        legacyDrinks: [Drink],
        scans: [Scan] = []
    ) {
        struct Accumulator {
            let identity: BeerLibraryIdentity
            var journalEntries: [JournalEntry] = []
            var encounters: [BeerTasteRecord] = []
            var savedScans: [Scan] = []
        }

        var accumulators: [BeerLibraryIdentity: Accumulator] = [:]
        var remainingDrinks = legacyDrinks.filter { !$0.isDeleted }

        // Consume at most one mirrored Drink for every Journal record. Shared
        // IDs win when encountered in migrated fixtures; otherwise photo or a
        // five-minute write window pairs the legacy schemas without erasing a
        // genuine older/newer encounter of the same beer.
        for entry in journalRecords.sorted(by: Self.journalRecordIsEarlier) {
            let pairedDrink = Self.pairedDrink(
                for: entry,
                candidates: remainingDrinks
            )
            if let pairedDrink {
                remainingDrinks.removeAll { $0.id == pairedDrink.id }
            }
            guard !entry.isDeleted else { continue }

            let identity = BeerLibraryIdentity(
                name: entry.beerName,
                brewery: entry.brand,
                recordID: entry.id
            )
            var accumulator = accumulators[identity] ?? Accumulator(identity: identity)
            accumulator.journalEntries.append(entry)
            accumulator.encounters.append(
                BeerTasteRecord(journalEntry: entry, pairedDrink: pairedDrink)
            )
            accumulators[identity] = accumulator
        }

        for drink in remainingDrinks {
            let identity = BeerLibraryIdentity(
                name: drink.name,
                brewery: drink.brand,
                recordID: drink.id
            )
            // Placeholder Drink records cannot support an exact personal claim
            // and cannot be safely reconciled after deletion. Keep a live
            // Journal placeholder, but exclude unpaired legacy placeholders.
            guard identity.isLookupEligible else { continue }
            var accumulator = accumulators[identity] ?? Accumulator(identity: identity)
            accumulator.encounters.append(BeerTasteRecord(legacyDrink: drink))
            accumulators[identity] = accumulator
        }

        for scan in scans where !scan.isDeleted && scan.wantToTry && scan.linkedJournalId == nil {
            let identity = BeerLibraryIdentity(
                name: scan.beerName,
                brewery: scan.brand,
                recordID: scan.id
            )
            var accumulator = accumulators[identity] ?? Accumulator(identity: identity)
            accumulator.savedScans.append(scan)
            accumulators[identity] = accumulator
        }

        items = accumulators.values.map { accumulator in
            BeerLibraryItem(
                id: accumulator.identity,
                journalEntries: accumulator.journalEntries.sorted(by: Self.journalRecordIsNewer),
                encounters: accumulator.encounters.sorted(by: Self.tasteRecordIsNewer),
                savedScans: accumulator.savedScans.sorted(by: Self.scanIsNewer)
            )
        }
        .sorted {
            if $0.latestActivityDate != $1.latestActivityDate {
                return $0.latestActivityDate > $1.latestActivityDate
            }
            return $0.id.stableSortKey < $1.id.stableSortKey
        }
    }

    var tasteRecords: [BeerTasteRecord] {
        items.flatMap(\.encounters).sorted(by: Self.tasteRecordIsNewer)
    }

    var triedItems: [BeerLibraryItem] { items.filter(\.isTried) }
    var savedItems: [BeerLibraryItem] { items.filter(\.isSaved) }

    func exactItem(name: String, brewery: String?) -> BeerLibraryItem? {
        let lookup = BeerLibraryIdentity(name: name, brewery: brewery, recordID: UUID())
        guard lookup.isLookupEligible else { return nil }
        return items.first { $0.id == lookup }
    }

    func latestRating(name: String, brewery: String?) -> Rating? {
        exactItem(name: name, brewery: brewery)?.latestRating
    }

    private static func pairedDrink(for entry: JournalEntry, candidates: [Drink]) -> Drink? {
        if let sameID = candidates.first(where: { $0.id == entry.id }) {
            return sameID
        }

        let identityMatches = candidates.filter {
            BeerLibraryIdentity.hasSameNormalizedTuple(
                name: entry.beerName,
                brewery: entry.brand,
                otherName: $0.name,
                otherBrewery: $0.brand
            )
        }
        guard !identityMatches.isEmpty else { return nil }

        if let photo = entry.photoFileName, !photo.isEmpty {
            let photoMatches = identityMatches.filter { $0.photoFileName == photo }
            if let closest = closestDrink(to: entry.dateLogged, in: photoMatches) {
                return closest
            }
        }

        guard let closest = closestDrink(to: entry.dateLogged, in: identityMatches),
              abs(closest.dateAdded.timeIntervalSince(entry.dateLogged)) <= 300 else {
            return nil
        }
        return closest
    }

    private static func closestDrink(to date: Date, in drinks: [Drink]) -> Drink? {
        drinks.min {
            let leftGap = abs($0.dateAdded.timeIntervalSince(date))
            let rightGap = abs($1.dateAdded.timeIntervalSince(date))
            if leftGap != rightGap { return leftGap < rightGap }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func journalRecordIsEarlier(_ lhs: JournalEntry, _ rhs: JournalEntry) -> Bool {
        if lhs.dateLogged != rhs.dateLogged { return lhs.dateLogged < rhs.dateLogged }
        if lhs.lastModifiedLocal != rhs.lastModifiedLocal {
            return lhs.lastModifiedLocal < rhs.lastModifiedLocal
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func journalRecordIsNewer(_ lhs: JournalEntry, _ rhs: JournalEntry) -> Bool {
        let leftDate = lhs.dateTried ?? lhs.dateLogged
        let rightDate = rhs.dateTried ?? rhs.dateLogged
        if leftDate != rightDate { return leftDate > rightDate }
        if lhs.lastModifiedLocal != rhs.lastModifiedLocal {
            return lhs.lastModifiedLocal > rhs.lastModifiedLocal
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func tasteRecordIsNewer(_ lhs: BeerTasteRecord, _ rhs: BeerTasteRecord) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func scanIsNewer(_ lhs: Scan, _ rhs: Scan) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
        if lhs.lastModifiedLocal != rhs.lastModifiedLocal {
            return lhs.lastModifiedLocal > rhs.lastModifiedLocal
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
