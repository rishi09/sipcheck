import XCTest
@testable import SipCheck

final class BeerLibraryProjectionTests: XCTestCase {
    private let older = Date(timeIntervalSince1970: 1_700_000_000)
    private let newer = Date(timeIntervalSince1970: 1_710_000_000)

    func testMirroredJournalAndDrinkCountOnceAndJournalWins() {
        let drink = makeDrink(rating: .dislike)
        let journal = makeJournal(rating: 5)

        let snapshot = BeerLibrarySnapshot(
            journalRecords: [journal],
            legacyDrinks: [drink]
        )

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.tasteRecords.count, 1)
        XCTAssertEqual(snapshot.tasteRecords.first?.source, .journal)
        XCTAssertEqual(snapshot.latestRating(name: journal.beerName, brewery: journal.brand), .like)
    }

    func testJournalEditImmediatelyOverridesStaleDrinkForProfileAndExactVerdict() {
        let drink = makeDrink(rating: .like)
        let journal = makeJournal(rating: 1)
        let snapshot = BeerLibrarySnapshot(journalRecords: [journal], legacyDrinks: [drink])
        let profile = TasteProfile.build(from: snapshot.tasteRecords)

        XCTAssertEqual(profile.likedCount, 0)
        XCTAssertEqual(profile.dislikedCount, 1)

        let assessment = TasteScorer.assessWithExactHistory(
            name: journal.beerName,
            brewery: journal.brand,
            style: .ipa,
            abv: 7,
            library: snapshot,
            profile: profile,
            preferences: emptyPreferences
        )
        XCTAssertEqual(assessment.verdict, .skipIt)
        XCTAssertTrue(assessment.shortReason.contains("wasn't for you last time"))
    }

    func testJournalTombstoneSuppressesStillLiveMirroredDrink() {
        let drink = makeDrink(rating: .like, date: older)
        var journal = makeJournal(rating: 5, date: older)
        journal.isDeleted = true

        let snapshot = BeerLibrarySnapshot(
            journalRecords: [journal],
            legacyDrinks: [drink]
        )

        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertTrue(snapshot.tasteRecords.isEmpty)
        XCTAssertNil(snapshot.latestRating(name: journal.beerName, brewery: journal.brand))
    }

    func testLegacyOnlyDrinkRemainsVisibleAndTasteActive() {
        let drink = makeDrink(name: "Legacy Lager", brewery: "Old Brewery", style: "Lager", rating: .like)
        let snapshot = BeerLibrarySnapshot(journalRecords: [], legacyDrinks: [drink])

        XCTAssertEqual(snapshot.triedItems.count, 1)
        XCTAssertEqual(snapshot.tasteRecords.first?.source, .legacyDrink)
        XCTAssertEqual(snapshot.latestRating(name: drink.name, brewery: drink.brand), .like)
    }

    func testMultipleJournalEncountersStaySeparateWithinOneBeer() {
        let first = makeJournal(rating: 2, date: older)
        let second = makeJournal(rating: 5, date: newer)
        let snapshot = BeerLibrarySnapshot(journalRecords: [first, second], legacyDrinks: [])

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.encounters.count, 2)
        XCTAssertEqual(snapshot.items.first?.latestRating, .like)
        XCTAssertEqual(snapshot.tasteRecords.count, 2)
    }

    func testSameNameDifferentKnownBreweriesStaySeparate() {
        let first = makeJournal(name: "Shared Name", brewery: "North Brewing", rating: 5)
        let second = makeJournal(name: "Shared Name", brewery: "South Brewing", rating: 1)
        let snapshot = BeerLibrarySnapshot(journalRecords: [first, second], legacyDrinks: [])

        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.latestRating(name: "Shared Name", brewery: "North Brewing"), .like)
        XCTAssertEqual(snapshot.latestRating(name: "Shared Name", brewery: "South Brewing"), .dislike)
    }

    func testMissingBreweryNeverJoinsKnownBrewery() {
        let unbranded = makeJournal(name: "Shared Name", brewery: "", rating: 5)
        let branded = makeDrink(name: "Shared Name", brewery: "Known Brewery", rating: .dislike)
        let snapshot = BeerLibrarySnapshot(journalRecords: [unbranded], legacyDrinks: [branded])

        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.latestRating(name: "Shared Name", brewery: nil), .like)
        XCTAssertEqual(snapshot.latestRating(name: "Shared Name", brewery: "Known Brewery"), .dislike)
    }

    func testIdentityNormalizesCaseDiacriticsApostrophesAndPunctuation() {
        let journal = makeJournal(
            name: "Bell’s Two-Hearted",
            brewery: "Bréw Co.",
            rating: 4
        )
        let drink = makeDrink(
            name: "BELLS TWO HEARTED",
            brewery: "Brew Co",
            rating: .dislike
        )
        let snapshot = BeerLibrarySnapshot(journalRecords: [journal], legacyDrinks: [drink])

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.tasteRecords.count, 1)
        XCTAssertEqual(snapshot.latestRating(name: "Bells Two Hearted", brewery: "Brew Co"), .like)
    }

    func testSavedScansJoinStrictIdentityAndLinkedScansAreExcluded() {
        let journal = makeJournal(rating: 5)
        let matching = Scan(
            beerName: journal.beerName,
            brand: journal.brand,
            verdict: .tryIt,
            wantToTry: true
        )
        let otherBrewery = Scan(
            beerName: journal.beerName,
            brand: "Other Brewery",
            verdict: .yourCall,
            wantToTry: true
        )
        let linked = Scan(
            beerName: "Already Linked",
            verdict: .tryIt,
            wantToTry: true,
            linkedJournalId: journal.id
        )

        let snapshot = BeerLibrarySnapshot(
            journalRecords: [journal],
            legacyDrinks: [],
            scans: [matching, otherBrewery, linked]
        )

        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.exactItem(name: journal.beerName, brewery: journal.brand)?.savedScans.count, 1)
        XCTAssertEqual(snapshot.savedItems.count, 1)
        XCTAssertEqual(snapshot.savedItems.first?.brewery, "Other Brewery")
        XCTAssertNil(snapshot.exactItem(name: "Already Linked", brewery: nil))
    }

    func testSharedIDMigrationFixtureSuppressesMirrorAfterMetadataDiverges() {
        let sharedID = UUID()
        let journal = makeJournal(
            id: sharedID,
            name: "Renamed Beer",
            brewery: "Brewery",
            rating: 5
        )
        let drink = makeDrink(
            id: sharedID,
            name: "Old Beer Name",
            brewery: "Brewery",
            rating: .dislike
        )
        let snapshot = BeerLibrarySnapshot(journalRecords: [journal], legacyDrinks: [drink])

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.name, "Renamed Beer")
        XCTAssertNil(snapshot.exactItem(name: "Old Beer Name", brewery: "Brewery"))
    }

    func testUnpairedUnknownBeerPlaceholdersCannotCreatePersonalEvidence() {
        let first = makeDrink(name: "Unknown Beer", brewery: "", rating: .like)
        let second = makeDrink(name: "Unknown Beer", brewery: "", rating: .dislike)
        let snapshot = BeerLibrarySnapshot(journalRecords: [], legacyDrinks: [first, second])

        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertNil(snapshot.exactItem(name: "Unknown Beer", brewery: nil))
    }

    func testJournalMirrorPairingPreservesOlderLegacyEncounterOfSameBeer() {
        let oldLegacy = makeDrink(rating: .dislike, date: older)
        let mirroredDrink = makeDrink(rating: .like, date: newer)
        let journal = makeJournal(rating: 5, date: newer)

        let snapshot = BeerLibrarySnapshot(
            journalRecords: [journal],
            legacyDrinks: [oldLegacy, mirroredDrink]
        )

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.tasteRecords.count, 2)
        XCTAssertEqual(snapshot.tasteRecords.filter { $0.source == .journal }.count, 1)
        XCTAssertEqual(snapshot.tasteRecords.filter { $0.source == .legacyDrink }.count, 1)
    }

    func testJournalTombstoneSuppressesOnlyItsMirrorNotNewerLegacyEncounter() {
        let mirroredDrink = makeDrink(rating: .like, date: older)
        let newerLegacy = makeDrink(rating: .dislike, date: newer)
        var tombstone = makeJournal(rating: 5, date: older)
        tombstone.isDeleted = true

        let snapshot = BeerLibrarySnapshot(
            journalRecords: [tombstone],
            legacyDrinks: [mirroredDrink, newerLegacy]
        )

        XCTAssertEqual(snapshot.tasteRecords.count, 1)
        XCTAssertEqual(snapshot.tasteRecords.first?.source, .legacyDrink)
        XCTAssertEqual(snapshot.tasteRecords.first?.rating, .dislike)
    }

    func testPairedDrinkFillsServingTypeWithoutOverridingJournalRating() {
        let drink = makeDrink(rating: .dislike, type: .draft, date: older)
        let journal = makeJournal(rating: 5, date: older)

        let snapshot = BeerLibrarySnapshot(journalRecords: [journal], legacyDrinks: [drink])

        XCTAssertEqual(snapshot.tasteRecords.first?.source, .journal)
        XCTAssertEqual(snapshot.tasteRecords.first?.rating, .like)
        XCTAssertEqual(snapshot.tasteRecords.first?.drinkType, .draft)
    }

    func testEqualEncounterDatesUseModificationTimeAsStableLatestTieBreak() {
        let sharedDate = older
        var olderEdit = makeJournal(rating: 1, date: sharedDate)
        olderEdit.lastModifiedLocal = sharedDate
        var newerEdit = makeJournal(rating: 5, date: sharedDate)
        newerEdit.lastModifiedLocal = newer

        let forward = BeerLibrarySnapshot(
            journalRecords: [olderEdit, newerEdit],
            legacyDrinks: []
        )
        let reversed = BeerLibrarySnapshot(
            journalRecords: [newerEdit, olderEdit],
            legacyDrinks: []
        )

        XCTAssertEqual(forward.items.first?.latestRating, .like)
        XCTAssertEqual(reversed.items.first?.latestRating, .like)
    }

    private var emptyPreferences: TastePreferences {
        TastePreferences(vibe: "", adventure: "", dislikes: [])
    }

    private func makeDrink(
        id: UUID = UUID(),
        name: String = "Two Hearted Ale",
        brewery: String = "Bell's",
        style: String = "IPA",
        rating: Rating,
        type: DrinkType = .regular,
        date: Date? = nil
    ) -> Drink {
        var drink = Drink(
            id: id,
            name: name,
            brand: brewery,
            style: style,
            rating: rating,
            type: type,
            abv: 7
        )
        if let date { drink.dateAdded = date }
        return drink
    }

    private func makeJournal(
        id: UUID = UUID(),
        name: String = "Two Hearted Ale",
        brewery: String = "Bell's",
        style: String = "IPA",
        rating: Int,
        date: Date? = nil
    ) -> JournalEntry {
        JournalEntry(
            id: id,
            beerName: name,
            brand: brewery,
            style: style,
            abv: 7,
            rating: rating,
            dateLogged: date ?? Date()
        )
    }
}
