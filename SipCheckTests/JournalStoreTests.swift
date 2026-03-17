import XCTest
@testable import SipCheck

final class JournalStoreTests: XCTestCase {

    private var store: JournalStore!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SipCheckTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = JournalStore(storageDirectory: tempDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        store = nil
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Add

    func testAddEntry() {
        let entry = JournalEntry(beerName: "Test IPA", brand: "Test Brewery", style: "IPA", rating: 4)
        store.addEntry(entry)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.beerName, "Test IPA")
    }

    func testAddEntryInsertsAtFront() {
        let first = JournalEntry(beerName: "First Beer", rating: 3)
        let second = JournalEntry(beerName: "Second Beer", rating: 5)

        store.addEntry(first)
        store.addEntry(second)

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries[0].beerName, "Second Beer")
        XCTAssertEqual(store.entries[1].beerName, "First Beer")
    }

    // MARK: - Delete

    func testDeleteEntry() {
        let entry = JournalEntry(beerName: "Delete Me", rating: 1)
        store.addEntry(entry)
        XCTAssertEqual(store.entries.count, 1)

        store.deleteEntry(entry)
        XCTAssertEqual(store.entries.count, 0)
    }

    func testDeleteNonExistentEntryDoesNothing() {
        let existing = JournalEntry(beerName: "Existing", rating: 3)
        let nonExistent = JournalEntry(beerName: "Ghost", rating: 3)

        store.addEntry(existing)
        store.deleteEntry(nonExistent)

        XCTAssertEqual(store.entries.count, 1)
    }

    // MARK: - Update

    func testUpdateEntry() {
        var entry = JournalEntry(beerName: "Original Name", brand: "Brewery", style: "IPA", rating: 3)
        store.addEntry(entry)

        entry.beerName = "Updated Name"
        entry.rating = 5
        store.updateEntry(entry)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.beerName, "Updated Name")
        XCTAssertEqual(store.entries.first?.rating, 5)
    }

    // MARK: - Persistence

    func testPersistenceAcrossInstances() {
        let entry = JournalEntry(beerName: "Persistent Beer", brand: "Brewery", style: "Stout", rating: 4)
        store.addEntry(entry)

        let store2 = JournalStore(storageDirectory: tempDirectory)

        XCTAssertEqual(store2.entries.count, 1)
        XCTAssertEqual(store2.entries.first?.beerName, "Persistent Beer")
        XCTAssertEqual(store2.entries.first?.rating, 4)
    }

    func testDeletePersists() {
        let entry = JournalEntry(beerName: "Will Be Deleted", rating: 2)
        store.addEntry(entry)
        store.deleteEntry(entry)

        let store2 = JournalStore(storageDirectory: tempDirectory)
        XCTAssertEqual(store2.entries.count, 0)
    }

    // MARK: - Corrupt / Missing Data

    func testLoadFromCorruptFile() {
        let fileURL = tempDirectory.appendingPathComponent("journal.json")
        try? "not valid json {{{{".data(using: .utf8)?.write(to: fileURL)

        let corruptStore = JournalStore(storageDirectory: tempDirectory)
        XCTAssertEqual(corruptStore.entries.count, 0, "Should gracefully handle corrupt data")
    }

    func testLoadFromMissingFile() {
        let freshStore = JournalStore(storageDirectory: tempDirectory)
        XCTAssertEqual(freshStore.entries.count, 0)
    }

    // MARK: - Queries

    func testRecentEntriesReturnsMaxFive() {
        for i in 1...8 {
            store.addEntry(JournalEntry(beerName: "Beer \(i)", rating: 3))
        }

        XCTAssertEqual(store.recentEntries.count, 5)
    }

    func testLovedEntries() {
        store.addEntry(JournalEntry(beerName: "Great Beer", rating: 5))
        store.addEntry(JournalEntry(beerName: "Good Beer", rating: 4))
        store.addEntry(JournalEntry(beerName: "Meh Beer", rating: 3))
        store.addEntry(JournalEntry(beerName: "Bad Beer", rating: 1))

        let loved = store.lovedEntries
        XCTAssertEqual(loved.count, 2)
        let lovedNames = loved.map { $0.beerName }
        XCTAssertTrue(lovedNames.contains("Great Beer"))
        XCTAssertTrue(lovedNames.contains("Good Beer"))
    }

    func testAverageRating() {
        store.addEntry(JournalEntry(beerName: "Beer 1", rating: 5))
        store.addEntry(JournalEntry(beerName: "Beer 2", rating: 3))
        store.addEntry(JournalEntry(beerName: "Beer 3", rating: 1))

        let avg = store.averageRating
        XCTAssertNotNil(avg)
        XCTAssertEqual(avg!, 3.0, accuracy: 0.01)
    }

    func testAverageRatingNilWhenEmpty() {
        XCTAssertNil(store.averageRating)
    }

    func testFindMatch() {
        store.addEntry(JournalEntry(beerName: "Sierra Nevada Pale Ale", brand: "Sierra Nevada", style: "Pale Ale", rating: 5))

        let result = store.findMatch(for: "Sierra Nevada")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.beerName, "Sierra Nevada Pale Ale")
    }

    // MARK: - Rating Clamping

    func testRatingClampedToRange() {
        let tooLow = JournalEntry(beerName: "Low", rating: 0)
        XCTAssertEqual(tooLow.rating, 1, "Rating below 1 should be clamped to 1")

        let tooHigh = JournalEntry(beerName: "High", rating: 10)
        XCTAssertEqual(tooHigh.rating, 5, "Rating above 5 should be clamped to 5")

        let normal = JournalEntry(beerName: "Normal", rating: 3)
        XCTAssertEqual(normal.rating, 3)
    }

    // MARK: - Seed Data

    func testSeedDataMode() {
        let seededStore = JournalStore(storageDirectory: tempDirectory, useSeedData: true)

        XCTAssertEqual(seededStore.entries.count, 3, "Seed data should contain 3 entries")

        let names = seededStore.entries.map { $0.beerName }
        XCTAssertTrue(names.contains("Sierra Nevada Pale Ale"))
        XCTAssertTrue(names.contains("Guinness Draught"))
        XCTAssertTrue(names.contains("Bud Light"))
    }
}
