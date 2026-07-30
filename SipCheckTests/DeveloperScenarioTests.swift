import XCTest
@testable import SipCheck

final class DeveloperScenarioTests: XCTestCase {
    override func tearDown() {
        DeveloperScenario.clearCurrent()
        super.tearDown()
    }

    func testLaunchArgumentParsesSplitAndInlineForms() {
        XCTAssertEqual(
            DeveloperScenario.requested(in: ["SipCheck", "--developer-scenario", "rich-history"]),
            .richHistory
        )
        XCTAssertEqual(
            DeveloperScenario.requested(in: ["SipCheck", "--developer-scenario=saved-only"]),
            .savedOnly
        )
        XCTAssertNil(DeveloperScenario.requested(in: ["SipCheck", "--developer-scenario", "unknown"]))
    }

    func testFixturesRepresentFourDistinctProductStates() {
        let empty = DeveloperScenario.empty.fixture
        XCTAssertTrue(empty.drinks.isEmpty)
        XCTAssertTrue(empty.scans.isEmpty)
        XCTAssertTrue(empty.journalEntries.isEmpty)

        let rich = DeveloperScenario.richHistory.fixture
        let richSnapshot = BeerLibrarySnapshot(
            journalRecords: rich.journalEntries,
            legacyDrinks: rich.drinks,
            scans: rich.scans
        )
        XCTAssertEqual(rich.drinks.count, 3)
        XCTAssertEqual(rich.journalEntries.count, 3)
        XCTAssertEqual(richSnapshot.tasteRecords.count, 3)
        XCTAssertEqual(Set(richSnapshot.tasteRecords.map(\.style)).count, 3)

        let saved = DeveloperScenario.savedOnly.fixture
        let savedSnapshot = BeerLibrarySnapshot(
            journalRecords: saved.journalEntries,
            legacyDrinks: saved.drinks,
            scans: saved.scans
        )
        XCTAssertTrue(saved.drinks.isEmpty)
        XCTAssertTrue(saved.journalEntries.isEmpty)
        XCTAssertEqual(savedSnapshot.savedItems.count, 3)
        XCTAssertTrue(saved.scans.allSatisfy(\.wantToTry))

        XCTAssertEqual(DeveloperScenario.error.fixture.drinks.count, 0)
        XCTAssertEqual(DeveloperScenario.error.initialTab, 0)
        XCTAssertEqual(DeveloperScenario.richHistory.initialTab, 1)
    }

    func testApplyingScenarioReplacesAndPersistsTheWholeIsolatedSandbox() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeveloperScenarioTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let drinkStore = DrinkStore(storageDirectory: directory)
        let scanStore = ScanStore(storageDirectory: directory)
        let journalStore = JournalStore(storageDirectory: directory)

        DeveloperScenario.richHistory.apply(
            drinkStore: drinkStore,
            scanStore: scanStore,
            journalStore: journalStore,
            notify: false
        )
        XCTAssertEqual(drinkStore.drinks.count, 3)
        XCTAssertEqual(journalStore.entries.count, 3)
        XCTAssertEqual(scanStore.scans.count, 3)
        XCTAssertEqual(DeveloperScenario.current, .richHistory)

        DeveloperScenario.savedOnly.apply(
            drinkStore: drinkStore,
            scanStore: scanStore,
            journalStore: journalStore,
            notify: false
        )
        XCTAssertTrue(drinkStore.syncRecords.isEmpty)
        XCTAssertTrue(journalStore.syncRecords.isEmpty)
        XCTAssertEqual(scanStore.syncRecords.count, 3)
        XCTAssertTrue(scanStore.scans.allSatisfy(\.wantToTry))

        let reloadedDrinks = DrinkStore(storageDirectory: directory)
        let reloadedScans = ScanStore(storageDirectory: directory)
        let reloadedJournal = JournalStore(storageDirectory: directory)
        XCTAssertTrue(reloadedDrinks.syncRecords.isEmpty)
        XCTAssertTrue(reloadedJournal.syncRecords.isEmpty)
        XCTAssertEqual(reloadedScans.wantToTryScans.count, 3)

        DeveloperScenario.empty.apply(
            drinkStore: drinkStore,
            scanStore: scanStore,
            journalStore: journalStore,
            notify: false
        )
        XCTAssertTrue(drinkStore.syncRecords.isEmpty)
        XCTAssertTrue(scanStore.syncRecords.isEmpty)
        XCTAssertTrue(journalStore.syncRecords.isEmpty)
    }
}
