import XCTest
@testable import SipCheck

final class StoreIntegrationTests: XCTestCase {
    private var testDir: URL!

    override func setUp() {
        super.setUp()
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreIntegrationTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
        testDir = nil
        super.tearDown()
    }

    // MARK: - Test 1: Add drink via store, then find it via findMatch (DrinkStore + BeerMatcher wiring)

    func testAddThenFind() {
        let store = DrinkStore(storageDirectory: testDir)

        let drink = Drink(
            name: "Lagunitas IPA",
            brand: "Lagunitas",
            style: "IPA",
            rating: .like,
            notes: "Hoppy and bold"
        )
        store.addDrink(drink)

        // Verify findMatch routes through BeerMatcher and locates the drink
        let exactMatch = store.findMatch(for: "Lagunitas IPA")
        XCTAssertNotNil(exactMatch, "Exact name should match")
        XCTAssertEqual(exactMatch?.name, "Lagunitas IPA")

        let partialMatch = store.findMatch(for: "Lagunitas")
        XCTAssertNotNil(partialMatch, "Partial name should match")
        XCTAssertEqual(partialMatch?.brand, "Lagunitas")

        let noMatch = store.findMatch(for: "Totally Unknown Brew")
        XCTAssertNil(noMatch, "Non-existent drink should return nil")
    }

    // MARK: - Test 2: Persist across separate store instances (real JSON roundtrip)

    func testPersistAcrossInstances() {
        // Instance 1: add drinks and let it save to disk
        let store1 = DrinkStore(storageDirectory: testDir)
        let drinkA = Drink(name: "Pliny the Elder", brand: "Russian River", style: "Double IPA", rating: .like)
        let drinkB = Drink(name: "Heady Topper", brand: "The Alchemist", style: "Double IPA", rating: .neutral)
        store1.addDrink(drinkA)
        store1.addDrink(drinkB)
        XCTAssertEqual(store1.drinks.count, 2)

        // Instance 2: loads from the same directory — should see both drinks
        let store2 = DrinkStore(storageDirectory: testDir)
        XCTAssertEqual(store2.drinks.count, 2, "Second instance should load both drinks from disk")

        let names = store2.drinks.map { $0.name }
        XCTAssertTrue(names.contains("Pliny the Elder"))
        XCTAssertTrue(names.contains("Heady Topper"))

        // Verify full fidelity of deserialized fields
        let pliny = store2.drinks.first { $0.name == "Pliny the Elder" }
        XCTAssertEqual(pliny?.brand, "Russian River")
        XCTAssertEqual(pliny?.style, "Double IPA")
        XCTAssertEqual(pliny?.rating, .like)

        // Verify the JSON file actually exists on disk
        let fileURL = testDir.appendingPathComponent("drinks.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "drinks.json should exist on disk")
    }

    // MARK: - Test 3: Rapidly add multiple drinks — none lost, file not corrupted

    func testConcurrentWrites() {
        let store = DrinkStore(storageDirectory: testDir)
        let drinkCount = 15

        // Rapidly add drinks in a tight loop
        for i in 1...drinkCount {
            let drink = Drink(
                name: "Rapid Beer \(i)",
                brand: "Brewery \(i)",
                style: i % 2 == 0 ? "IPA" : "Stout",
                rating: i % 3 == 0 ? .dislike : .like
            )
            store.addDrink(drink)
        }

        // All drinks should be present in memory
        XCTAssertEqual(store.drinks.count, drinkCount, "All \(drinkCount) drinks should be in memory")

        // Verify file is not corrupted by loading into a fresh instance
        let verifyStore = DrinkStore(storageDirectory: testDir)
        XCTAssertEqual(verifyStore.drinks.count, drinkCount,
                       "All \(drinkCount) drinks should survive serialization roundtrip")

        // Spot-check first and last drink names exist
        let names = verifyStore.drinks.map { $0.name }
        XCTAssertTrue(names.contains("Rapid Beer 1"), "First drink should be present")
        XCTAssertTrue(names.contains("Rapid Beer \(drinkCount)"), "Last drink should be present")

        // Verify every single drink is accounted for
        for i in 1...drinkCount {
            XCTAssertTrue(names.contains("Rapid Beer \(i)"), "Rapid Beer \(i) should be present")
        }
    }
}
