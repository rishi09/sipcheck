import XCTest
@testable import SipCheck

final class DrinkStoreTests: XCTestCase {

    private var store: DrinkStore!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        // Create isolated temp directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SipCheckTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = DrinkStore(storageDirectory: tempDirectory)
    }

    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        store = nil
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Add

    func testAddDrink() {
        let drink = Drink(name: "Test IPA", brand: "Test Brewery", style: "IPA", rating: .like)
        store.addDrink(drink)

        XCTAssertEqual(store.drinks.count, 1)
        XCTAssertEqual(store.drinks.first?.name, "Test IPA")
    }

    func testAddDrinkInsertsAtFront() {
        let first = Drink(name: "First Beer", rating: .neutral)
        let second = Drink(name: "Second Beer", rating: .like)

        store.addDrink(first)
        store.addDrink(second)

        XCTAssertEqual(store.drinks.count, 2)
        XCTAssertEqual(store.drinks[0].name, "Second Beer")
        XCTAssertEqual(store.drinks[1].name, "First Beer")
    }

    // MARK: - Delete

    func testDeleteDrink() {
        let drink = Drink(name: "Delete Me", rating: .dislike)
        store.addDrink(drink)
        XCTAssertEqual(store.drinks.count, 1)

        store.deleteDrink(drink)
        XCTAssertEqual(store.drinks.count, 0)
    }

    func testDeleteNonExistentDrinkDoesNothing() {
        let existing = Drink(name: "Existing", rating: .neutral)
        let nonExistent = Drink(name: "Ghost", rating: .neutral)

        store.addDrink(existing)
        store.deleteDrink(nonExistent)

        XCTAssertEqual(store.drinks.count, 1)
    }

    // MARK: - Update

    func testUpdateDrink() {
        var drink = Drink(name: "Original Name", brand: "Brewery", style: "IPA", rating: .neutral)
        store.addDrink(drink)

        drink.name = "Updated Name"
        drink.rating = .like
        store.updateDrink(drink)

        XCTAssertEqual(store.drinks.count, 1)
        XCTAssertEqual(store.drinks.first?.name, "Updated Name")
        XCTAssertEqual(store.drinks.first?.rating, .like)
    }

    // MARK: - Persistence

    func testPersistenceAcrossInstances() {
        let drink = Drink(name: "Persistent Beer", brand: "Brewery", style: "Stout", rating: .like)
        store.addDrink(drink)

        // Create new store instance pointing to same directory
        let store2 = DrinkStore(storageDirectory: tempDirectory)

        XCTAssertEqual(store2.drinks.count, 1)
        XCTAssertEqual(store2.drinks.first?.name, "Persistent Beer")
        XCTAssertEqual(store2.drinks.first?.rating, .like)
    }

    func testDeletePersists() {
        let drink = Drink(name: "Will Be Deleted", rating: .neutral)
        store.addDrink(drink)
        store.deleteDrink(drink)

        let store2 = DrinkStore(storageDirectory: tempDirectory)
        XCTAssertEqual(store2.drinks.count, 0)
    }

    // MARK: - Corrupt / Missing Data

    func testLoadFromCorruptFile() {
        // Write garbage to the drinks file
        let fileURL = tempDirectory.appendingPathComponent("drinks.json")
        try? "not valid json {{{{".data(using: .utf8)?.write(to: fileURL)

        let corruptStore = DrinkStore(storageDirectory: tempDirectory)
        XCTAssertEqual(corruptStore.drinks.count, 0, "Should gracefully handle corrupt data")
    }

    func testLoadFromMissingFile() {
        // tempDirectory exists but has no drinks.json
        let freshStore = DrinkStore(storageDirectory: tempDirectory)
        XCTAssertEqual(freshStore.drinks.count, 0)
    }

    // MARK: - Queries

    func testRecentDrinksReturnsMaxThree() {
        for i in 1...5 {
            store.addDrink(Drink(name: "Beer \(i)", rating: .neutral))
        }

        XCTAssertEqual(store.recentDrinks.count, 3)
    }

    func testFindMatch() {
        store.addDrink(Drink(name: "Sierra Nevada Pale Ale", brand: "Sierra Nevada", style: "Pale Ale", rating: .like))

        let result = store.findMatch(for: "Sierra Nevada")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "Sierra Nevada Pale Ale")
    }

    // MARK: - Seed Data

    func testSeedDataMode() {
        let seededStore = DrinkStore(storageDirectory: tempDirectory, useSeedData: true)

        XCTAssertEqual(seededStore.drinks.count, 3, "Seed data should contain 3 drinks")

        let names = seededStore.drinks.map { $0.name }
        XCTAssertTrue(names.contains("Sierra Nevada Pale Ale"))
        XCTAssertTrue(names.contains("Guinness Draught"))
        XCTAssertTrue(names.contains("Bud Light"))
    }
}
