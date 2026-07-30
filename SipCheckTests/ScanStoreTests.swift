import XCTest
@testable import SipCheck

final class ScanStoreTests: XCTestCase {

    private var store: ScanStore!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SipCheckTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = ScanStore(storageDirectory: tempDirectory)
    }

    override func tearDown() {
        store?.flushPersistence()
        try? FileManager.default.removeItem(at: tempDirectory)
        store = nil
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Add

    func testAddScan() {
        let scan = Scan(beerName: "Test IPA", style: "IPA", abv: 6.5, verdict: .tryIt, explanation: "Looks great")
        store.addScan(scan)

        XCTAssertEqual(store.scans.count, 1)
        XCTAssertEqual(store.scans.first?.beerName, "Test IPA")
    }

    func testAddScanInsertsAtFront() {
        let first = Scan(beerName: "First Beer", explanation: "First")
        let second = Scan(beerName: "Second Beer", explanation: "Second")

        store.addScan(first)
        store.addScan(second)

        XCTAssertEqual(store.scans.count, 2)
        XCTAssertEqual(store.scans[0].beerName, "Second Beer")
        XCTAssertEqual(store.scans[1].beerName, "First Beer")
    }

    // MARK: - Delete

    func testDeleteScan() {
        let scan = Scan(beerName: "Delete Me", verdict: .skipIt, explanation: "Bad")
        store.addScan(scan)
        XCTAssertEqual(store.scans.count, 1)

        store.deleteScan(scan)
        XCTAssertEqual(store.scans.count, 0)
    }

    func testDeleteNonExistentScanDoesNothing() {
        let existing = Scan(beerName: "Existing", explanation: "Here")
        let nonExistent = Scan(beerName: "Ghost", explanation: "Gone")

        store.addScan(existing)
        store.deleteScan(nonExistent)

        XCTAssertEqual(store.scans.count, 1)
    }

    // MARK: - Update

    func testUpdateScan() {
        var scan = Scan(beerName: "Original", verdict: .yourCall, explanation: "Maybe")
        store.addScan(scan)

        scan.verdict = .tryIt
        scan.wantToTry = true
        store.updateScan(scan)

        XCTAssertEqual(store.scans.count, 1)
        XCTAssertEqual(store.scans.first?.verdict, .tryIt)
        XCTAssertEqual(store.scans.first?.wantToTry, true)
    }

    // MARK: - Persistence

    func testPersistenceAcrossInstances() {
        let source = BeerFactSource(
            kind: .webSearch,
            url: URL(string: "https://persistent-brewing.example/beers/persistent-ipa")!
        )!
        let scan = Scan(
            beerName: "Persistent IPA",
            brand: "Persistent Brewing",
            style: "IPA",
            photoFileName: "scan-photo.jpg",
            verdict: .tryIt,
            explanation: "Great",
            factSource: source
        )
        store.addScan(scan)
        store.flushPersistence()

        let store2 = ScanStore(storageDirectory: tempDirectory)

        XCTAssertEqual(store2.scans.count, 1)
        XCTAssertEqual(store2.scans.first?.beerName, "Persistent IPA")
        XCTAssertEqual(store2.scans.first?.brand, "Persistent Brewing")
        XCTAssertEqual(store2.scans.first?.photoFileName, "scan-photo.jpg")
        XCTAssertEqual(store2.scans.first?.verdict, .tryIt)
        XCTAssertEqual(store2.scans.first?.factSource, source)
    }

    func testLegacyAndMalformedFactSourcesDoNotDiscardScan() throws {
        let legacy = try JSONDecoder().decode(
            Scan.self,
            from: Data(#"{"beerName":"Legacy Beer"}"#.utf8)
        )
        XCTAssertEqual(legacy.beerName, "Legacy Beer")
        XCTAssertNil(legacy.factSource)

        let malformed = try JSONDecoder().decode(
            Scan.self,
            from: Data(
                #"{"beerName":"Still Readable","factSource":{"kind":"webSearch","url":"http://unsafe.example/beer"}}"#.utf8
            )
        )
        XCTAssertEqual(malformed.beerName, "Still Readable")
        XCTAssertNil(malformed.factSource)
    }

    func testCloudKitMetadataCodecRoundTripsSourceAndOriginWithoutNewFields() throws {
        let source = try XCTUnwrap(BeerFactSource(
            kind: .catalogBeer,
            url: URL(string: "https://catalog.beer/beer/source-aware-ipa")!
        ))

        let encoded = try XCTUnwrap(CloudKitScanMetadataCodec.encode(
            origin: "Brewed in Long Beach.",
            factSource: source
        ))
        let decoded = CloudKitScanMetadataCodec.decode(encoded)

        XCTAssertTrue(encoded.hasPrefix("SipCheck source v1 - Catalog.beer: https://"))
        XCTAssertEqual(decoded.origin, "Brewed in Long Beach.")
        XCTAssertEqual(decoded.factSource, source)
    }

    func testCloudKitMetadataCodecRoundTripsWebSourceWithoutOrigin() throws {
        let source = try XCTUnwrap(BeerFactSource(
            kind: .webSearch,
            url: URL(string: "https://source-aware.example/beers/ipa")!
        ))

        let encoded = try XCTUnwrap(CloudKitScanMetadataCodec.encode(
            origin: nil,
            factSource: source
        ))
        let decoded = CloudKitScanMetadataCodec.decode(encoded)

        XCTAssertTrue(encoded.hasPrefix("SipCheck source v1 - Brewery website: https://"))
        XCTAssertNil(decoded.origin)
        XCTAssertEqual(decoded.factSource, source)
    }

    func testCloudKitMetadataCodecRoundTripsBrandWithoutSchemaChange() throws {
        let source = try XCTUnwrap(BeerFactSource(
            kind: .catalogBeer,
            url: URL(string: "https://catalog.beer/beer/sierra-nevada-pale-ale")!
        ))

        let encoded = try XCTUnwrap(CloudKitScanMetadataCodec.encode(
            origin: "California",
            factSource: source,
            brand: "Sierra Nevada Brewing Company"
        ))
        let decoded = CloudKitScanMetadataCodec.decode(encoded)

        XCTAssertTrue(encoded.hasPrefix("SipCheck metadata v2: "))
        XCTAssertEqual(decoded.origin, "California")
        XCTAssertEqual(decoded.factSource, source)
        XCTAssertEqual(decoded.brand, "Sierra Nevada Brewing Company")
    }

    func testCloudKitMetadataCodecPreservesLegacyAndMalformedOrigins() {
        let legacy = "A legacy brewery origin story."
        XCTAssertEqual(CloudKitScanMetadataCodec.decode(legacy).origin, legacy)
        XCTAssertNil(CloudKitScanMetadataCodec.decode(legacy).factSource)
        XCTAssertNil(CloudKitScanMetadataCodec.decode(legacy).brand)

        let malformed = "SipCheck source v1 - Catalog.beer: http://unsafe.example/beer"
        XCTAssertEqual(CloudKitScanMetadataCodec.decode(malformed).origin, malformed)
        XCTAssertNil(CloudKitScanMetadataCodec.decode(malformed).factSource)
    }

    func testCloudKitBrandBackfillPreservesNewerRemoteState() {
        let id = UUID()
        var local = Scan(
            id: id,
            beerName: "Shared Beer",
            brand: "Local Brewery",
            verdict: .tryIt,
            explanation: "Older local explanation"
        )
        local.lastModifiedLocal = Date(timeIntervalSince1970: 100)
        var remote = Scan(
            id: id,
            beerName: "Shared Beer",
            verdict: .skipIt,
            explanation: "Newer remote explanation",
            wantToTry: true
        )
        remote.lastModifiedLocal = Date(timeIntervalSince1970: 200)

        let backfill = CloudKitSyncService.scansNeedingBrandBackfill(
            local: [local],
            remote: [remote]
        )

        XCTAssertEqual(backfill.count, 1)
        XCTAssertEqual(backfill.first?.brand, "Local Brewery")
        XCTAssertEqual(backfill.first?.verdict, .skipIt)
        XCTAssertEqual(backfill.first?.explanation, "Newer remote explanation")
        XCTAssertEqual(backfill.first?.wantToTry, true)
        XCTAssertEqual(backfill.first?.lastModifiedLocal, remote.lastModifiedLocal)
    }

    func testCloudKitBrandBackfillRejectsChangedRemoteIdentity() {
        let id = UUID()
        let local = Scan(id: id, beerName: "Original Beer", brand: "Old Brewery")
        let remote = Scan(id: id, beerName: "Corrected Beer", brand: nil)

        XCTAssertTrue(CloudKitSyncService.scansNeedingBrandBackfill(
            local: [local],
            remote: [remote]
        ).isEmpty)
    }

    @MainActor
    func testRemoteMergePreservesLocalOnlyPhotoAndBrand() {
        let local = Scan(
            beerName: "Local Beer",
            brand: "Local Brewery",
            photoFileName: "local-photo.jpg",
            explanation: "Local"
        )
        store.addScan(local)

        var remote = local
        remote.brand = nil
        remote.photoFileName = nil
        remote.explanation = "Newer remote copy"
        remote.lastModifiedLocal = Date().addingTimeInterval(60)
        store.applyRemoteScans([remote])

        XCTAssertEqual(store.scans.first?.brand, "Local Brewery")
        XCTAssertEqual(store.scans.first?.photoFileName, "local-photo.jpg")
        XCTAssertEqual(store.scans.first?.explanation, "Newer remote copy")
    }

    @MainActor
    func testRemoteMergeCarriesFactSource() {
        let local = Scan(beerName: "Synced Beer", explanation: "Local")
        store.addScan(local)
        let source = BeerFactSource(
            kind: .catalogBeer,
            url: URL(string: "https://catalog.beer/beer/synced-beer")!
        )!

        var remote = local
        remote.factSource = source
        remote.lastModifiedLocal = Date().addingTimeInterval(60)
        store.applyRemoteScans([remote])

        XCTAssertEqual(store.scans.first?.factSource, source)
    }

    @MainActor
    func testRemoteMergeDoesNotEraseLocalFactSource() {
        let source = BeerFactSource(
            kind: .webSearch,
            url: URL(string: "https://source-aware.example/beers/ipa")!
        )!
        let local = Scan(
            beerName: "Source Aware IPA",
            explanation: "Local",
            factSource: source
        )
        store.addScan(local)

        var remote = local
        remote.factSource = nil
        remote.explanation = "Newer remote copy"
        remote.lastModifiedLocal = Date().addingTimeInterval(60)
        store.applyRemoteScans([remote])

        XCTAssertEqual(store.scans.first?.explanation, "Newer remote copy")
        XCTAssertEqual(store.scans.first?.factSource, source)
    }

    func testMarkTriedClearsExactWantToTryDuplicatesAndLinksSource() {
        let source = Scan(beerName: "Bell's Two Hearted", wantToTry: false)
        let duplicate = Scan(beerName: "Bells Two Hearted", wantToTry: true)
        let unrelated = Scan(beerName: "Allagash White", wantToTry: true)
        store.addScan(source)
        store.addScan(duplicate)
        store.addScan(unrelated)
        let journalID = UUID()

        store.markTried(
            beerName: "Bell's Two Hearted",
            linkedJournalId: journalID,
            sourceScanId: source.id
        )

        XCTAssertEqual(store.scans.first(where: { $0.id == source.id })?.linkedJournalId, journalID)
        XCTAssertFalse(store.scans.first(where: { $0.id == duplicate.id })!.wantToTry)
        XCTAssertEqual(store.scans.first(where: { $0.id == duplicate.id })?.linkedJournalId, journalID)
        XCTAssertTrue(store.scans.first(where: { $0.id == unrelated.id })!.wantToTry)
        XCTAssertNil(store.scans.first(where: { $0.id == unrelated.id })?.linkedJournalId)

        let modified = store.scans.first(where: { $0.id == source.id })!.lastModifiedLocal
        store.markTried(
            beerName: "Bell's Two Hearted",
            linkedJournalId: journalID,
            sourceScanId: source.id
        )
        XCTAssertEqual(store.scans.first(where: { $0.id == source.id })?.lastModifiedLocal, modified)
    }

    func testMarkTriedDoesNotClearSameNameFromAnotherBrewery() {
        let north = Scan(
            beerName: "Shared Name",
            brand: "North Brewing",
            wantToTry: true
        )
        let south = Scan(
            beerName: "Shared Name",
            brand: "South Brewing",
            wantToTry: true
        )
        store.addScan(north)
        store.addScan(south)
        let journalID = UUID()

        store.markTried(
            beerName: "Shared Name",
            brewery: "North Brewing",
            linkedJournalId: journalID
        )

        XCTAssertFalse(store.scans.first(where: { $0.id == north.id })!.wantToTry)
        XCTAssertEqual(store.scans.first(where: { $0.id == north.id })?.linkedJournalId, journalID)
        XCTAssertTrue(store.scans.first(where: { $0.id == south.id })!.wantToTry)
        XCTAssertNil(store.scans.first(where: { $0.id == south.id })?.linkedJournalId)
    }

    func testDeletePersists() {
        let scan = Scan(beerName: "Will Be Deleted", explanation: "Bye")
        store.addScan(scan)
        store.deleteScan(scan)
        store.flushPersistence()

        let store2 = ScanStore(storageDirectory: tempDirectory)
        XCTAssertEqual(store2.scans.count, 0)
    }

    // MARK: - Corrupt / Missing Data

    func testLoadFromCorruptFile() {
        let fileURL = tempDirectory.appendingPathComponent("scans.json")
        try? "not valid json {{{{".data(using: .utf8)?.write(to: fileURL)

        let corruptStore = ScanStore(storageDirectory: tempDirectory)
        XCTAssertEqual(corruptStore.scans.count, 0, "Should gracefully handle corrupt data")
    }

    func testLoadFromMissingFile() {
        let freshStore = ScanStore(storageDirectory: tempDirectory)
        XCTAssertEqual(freshStore.scans.count, 0)
    }

    // MARK: - Queries

    func testRecentScansReturnsMaxFive() {
        for i in 1...8 {
            store.addScan(Scan(beerName: "Beer \(i)", explanation: "Scan \(i)"))
        }

        XCTAssertEqual(store.recentScans.count, 5)
    }

    func testWantToTryScans() {
        let scan1 = Scan(beerName: "Want This", verdict: .tryIt, explanation: "Yes", wantToTry: true)
        let scan2 = Scan(beerName: "Not This", verdict: .skipIt, explanation: "No", wantToTry: false)
        let scan3 = Scan(beerName: "Already Tried", verdict: .tryIt, explanation: "Done", wantToTry: true, linkedJournalId: UUID())

        store.addScan(scan1)
        store.addScan(scan2)
        store.addScan(scan3)

        let wantToTry = store.wantToTryScans
        XCTAssertEqual(wantToTry.count, 1)
        XCTAssertEqual(wantToTry.first?.beerName, "Want This")
    }

    func testFindMatch() {
        store.addScan(Scan(beerName: "Lagunitas IPA", style: "IPA", verdict: .tryIt, explanation: "Good"))

        let result = store.findMatch(for: "Lagunitas")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.beerName, "Lagunitas IPA")
    }

    // MARK: - Seed Data

    func testSeedDataMode() {
        let seededStore = ScanStore(storageDirectory: tempDirectory, useSeedData: true)

        XCTAssertEqual(seededStore.scans.count, 3, "Seed data should contain 3 scans")

        let names = seededStore.scans.map { $0.beerName }
        XCTAssertTrue(names.contains("Lagunitas IPA"))
        XCTAssertTrue(names.contains("Bud Light Lime"))
        XCTAssertTrue(names.contains("Blue Moon"))
    }

    // MARK: - Verdict Enum

    func testVerdictRawValues() {
        XCTAssertEqual(Verdict.tryIt.rawValue, "try_it")
        XCTAssertEqual(Verdict.skipIt.rawValue, "skip_it")
        XCTAssertEqual(Verdict.yourCall.rawValue, "your_call")
        XCTAssertEqual(Verdict.allCases.count, 3)
    }
}
