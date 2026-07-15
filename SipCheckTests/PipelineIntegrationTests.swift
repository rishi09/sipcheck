import XCTest
@testable import SipCheck

final class PipelineIntegrationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        OpenAIService.useMockResponses = true
    }

    override func tearDown() {
        OpenAIService.useMockResponses = false
        super.tearDown()
    }

    // MARK: - End-to-End

    func testFullPipelineEndToEnd() async throws {
        let pipeline = ScanningPipeline.shared
        let result = try await pipeline.scan(image: UIImage())

        // Verify all expected fields are populated
        XCTAssertNotNil(result.beerInfo.name, "Beer name should be populated")
        XCTAssertFalse(result.beerInfo.name!.isEmpty, "Beer name should not be empty")

        XCTAssertNotNil(result.beerInfo.brand, "Brand should be populated")
        XCTAssertFalse(result.beerInfo.brand!.isEmpty, "Brand should not be empty")

        XCTAssertNotNil(result.beerInfo.style, "Style should be populated")

        XCTAssertEqual(result.scanSource, .mock, "Scan source should be .mock in mock mode")
        XCTAssertGreaterThanOrEqual(result.latencyMs, 0, "Latency should be non-negative")
    }

    // MARK: - Consistency

    func testPipelineConsistency() async throws {
        let pipeline = ScanningPipeline.shared

        let result1 = try await pipeline.scan(image: UIImage())
        let result2 = try await pipeline.scan(image: UIImage())

        // Mock mode should return deterministic results
        XCTAssertEqual(result1.beerInfo.name, result2.beerInfo.name, "Name should be consistent across runs")
        XCTAssertEqual(result1.beerInfo.brand, result2.beerInfo.brand, "Brand should be consistent across runs")
        XCTAssertEqual(result1.beerInfo.style, result2.beerInfo.style, "Style should be consistent across runs")
        XCTAssertEqual(result1.beerInfo.abv, result2.beerInfo.abv, "ABV should be consistent across runs")
        XCTAssertEqual(result1.scanSource, result2.scanSource, "Scan source should be consistent across runs")
    }

    // MARK: - Menu flow

    func testMenuParserRanksOneWinnerAndKeepsRunnerUp() {
        let menu = """
        IPAs
        Two Hearted IPA — 7.0% — $8
        Allagash White Wheat — 5.2% — $7
        """
        let preferences = TastePreferences(
            vibe: "",
            adventure: "Mix It Up",
            dislikes: [],
            goToStyles: [BeerStyle.ipa.rawValue]
        )

        let result = MenuParser.evaluate(
            menu,
            profile: TasteProfile(),
            preferences: preferences
        )

        XCTAssertEqual(result.ranked.count, 2, "Style section headers must not become beers")
        XCTAssertEqual(result.winner?.name, "Two Hearted IPA")
        XCTAssertEqual(result.ranked.dropFirst().first?.name, "Allagash White Wheat")
    }

    func testMenuParserHandlesTwoDecimalABVAndIgnoresDiscounts() {
        XCTAssertEqual(MenuParser.extractABV(from: "House Tripel — 7.25%"), 7.25)
        XCTAssertEqual(MenuParser.extractABV(from: "Happy hour 20% off — Lager 5.2%"), 5.2)
        XCTAssertEqual(MenuParser.extractABV(from: "Pale Ale — ABV: 6.5"), 6.5)
        XCTAssertEqual(MenuParser.extractABV(from: "Pilsner — ALC. 5.9 BY VOL"), 5.9)

        let imported = MenuParser.parse("House Pilsner — ALC. 5.9 BY VOL — $7")
        XCTAssertEqual(imported.first?.name, "House Pilsner")
        XCTAssertEqual(imported.first?.abv, 5.9)
    }

    func testUnresolvedLabelNameSkipsBottleCodesAndLegalCopy() {
        let ocr = """
        4143 12.18
        Orion
        OKINAWA'S CRAFT
        THE DRAFT
        BEER/BIERE
        633 mL 5% alc. / vol.
        """

        XCTAssertEqual(BeerResolver.suggestedLabelName(from: ocr), "Orion")
    }

    func testUnresolvedLabelNamePrefersRepeatedBrandOverCountryCopy() {
        let ocr = """
        BIA VIỆT
        PRIDE OF
        VIETNAN
        BIA VIỆT
        Cold Brew
        LAGER 3S
        """

        XCTAssertEqual(BeerResolver.suggestedLabelName(from: ocr), "BIA VIỆT")
    }

    func testUnresolvedLabelNameHandlesFastOCRLogoNoise() {
        let ocr = """
        11
        BIA VIỆT,
        ¥ItT•A•
        BIP.VIÈT
        LAGER
        """

        XCTAssertEqual(BeerResolver.suggestedLabelName(from: ocr), "BIA VIỆT")
    }

    func testUnresolvedLabelNameRejectsCountryAsLegalCopyContinuation() {
        let ocr = """
        TÜ HEINEKEN
        CHÁT LƯỢNG
        PRIDE OF
        VIETNAM
        BIA VIỆT
        Cold Brew
        LAGER
        """

        XCTAssertEqual(BeerResolver.suggestedLabelName(from: ocr), "BIA VIỆT")
    }

    func testUnresolvedLabelNameSkipsGenericStyleAndFindsLogoName() {
        let ocr = """
        HEADLANDSBREWING.COM
        HAZY IPA
        HAZY IPA
        WHOOSH!
        HAZY IPA
        6.5% ALC/VOL
        """

        XCTAssertEqual(BeerResolver.suggestedLabelName(from: ocr), "WHOOSH!")
    }

    func testStyleInferenceDoesNotTreatHopIngredientsAsIPA() {
        XCTAssertNil(TasteScorer.inferStyle(from: "Cold brewed beer\nHOPS\nWATER\nMALT"))
        XCTAssertEqual(TasteScorer.inferStyle(from: "LAGER\nHOPS\nWATER"), .lager)
        XCTAssertEqual(TasteScorer.inferStyle(from: "BIA VIET\nSLAGERS\nHOPS"), .lager)
        XCTAssertEqual(TasteScorer.inferStyle(from: "INDIA PALE ALE"), .ipa)
        XCTAssertEqual(TasteScorer.inferStyle(from: "Hoppy seasonal"), .ipa)
    }

    func testCatalogMatchesNumericFrontMarkInsideOCRBlob() {
        let catalog = BundledCatalog(seed: [
            (name: "805", brewery: "Firestone Walker", style: "American Blonde Ale", coarse: "pale ale", abv: 4.7)
        ])
        let ocr = """
        FIRESTONE WALKER
        BREWING COMPANY
        805
        PROPERLY CHILL
        """

        let result = catalog.lookup(name: ocr)
        XCTAssertEqual(result?.name, "805")
        XCTAssertEqual(result?.confidence, 0.95)
        XCTAssertEqual(result?.style, .paleAle)
    }

    func testEnrichmentPolicySpendsOnlyOnUncertainScans() {
        XCTAssertFalse(EnrichmentPolicy.shouldStart(
            nameIsGuess: false,
            startedStyleless: false,
            isMenu: false,
            onDeviceAvailable: false,
            onlineAvailable: true
        ), "A resolved label must not spend a paid request")
        XCTAssertTrue(EnrichmentPolicy.shouldStart(
            nameIsGuess: true,
            startedStyleless: false,
            isMenu: false,
            onDeviceAvailable: false,
            onlineAvailable: true
        ))
        XCTAssertFalse(EnrichmentPolicy.shouldStart(
            nameIsGuess: true,
            startedStyleless: false,
            isMenu: false,
            onDeviceAvailable: true,
            onlineAvailable: false
        ), "On-device text knowledge must not rename an already actionable graphic label")
        XCTAssertFalse(EnrichmentPolicy.shouldStart(
            nameIsGuess: true,
            startedStyleless: true,
            isMenu: false,
            onDeviceAvailable: true,
            onlineAvailable: false
        ), "Text-only knowledge must not guess facts for an unresolved graphic label")
        XCTAssertTrue(EnrichmentPolicy.shouldStart(
            nameIsGuess: false,
            startedStyleless: true,
            isMenu: false,
            onDeviceAvailable: true,
            onlineAvailable: false
        ))
        XCTAssertFalse(EnrichmentPolicy.shouldStart(
            nameIsGuess: true,
            startedStyleless: true,
            isMenu: true,
            onDeviceAvailable: true,
            onlineAvailable: true
        ))
    }

    func testVisualIdentityRequiresANameBeforeAcceptingFacts() {
        let styleOnly = OpenAIService.BeerExtractionResult(
            name: nil,
            brand: nil,
            style: .ipa,
            origin: nil
        )
        XCTAssertNil(ScanningPipeline.visualIdentityEnrichment(from: styleOnly, verdict: .yourCall))

        let named = OpenAIService.BeerExtractionResult(
            name: "Orion Premium Draft",
            brand: "Orion Breweries",
            style: .lager,
            origin: "Okinawa"
        )
        let accepted = ScanningPipeline.visualIdentityEnrichment(from: named, verdict: .yourCall)
        XCTAssertEqual(accepted?.name, "Orion Premium Draft")
        XCTAssertEqual(accepted?.style, .lager)
    }

    func testLiveScannerTranscriptUsesVisualReadingOrder() {
        let lines: [(text: String, bounds: CGRect)] = [
            ("7.0% ABV", CGRect(x: 20, y: 220, width: 100, height: 30)),
            ("TWO HEARTED", CGRect(x: 15, y: 80, width: 220, height: 40)),
            ("IPA", CGRect(x: 15, y: 150, width: 80, height: 30))
        ]

        XCTAssertEqual(LiveScanText.transcript(from: lines), "TWO HEARTED\nIPA\n7.0% ABV")
        XCTAssertTrue(LiveScanText.isUsable("ORION"))
        XCTAssertFalse(LiveScanText.isUsable("BEER MENU"))
        XCTAssertFalse(LiveScanText.isUsable("STOUT"))
        XCTAssertFalse(LiveScanText.isUsable("12"))
    }

    func testLiveScannerRegionStaysInsideCompactPhoneChrome() {
        let region = LiveScanLayout.region(in: CGSize(width: 375, height: 667))
        XCTAssertEqual(region.width, 327)
        XCTAssertLessThanOrEqual(region.height, 330)
        XCTAssertGreaterThan(region.minY, 150)
        XCTAssertLessThan(region.maxY, 510)
    }

    func testFoundationModelJSONUsesTheSharedStructuredParser() {
        let raw = """
        {"name":"Two Hearted Ale","brand":"Bell's","style":"IPA","abv":7.0,"origin":"Michigan"}
        """

        let result = ScanningPipeline.parseEnrichment(raw)
        XCTAssertEqual(result?.name, "Two Hearted Ale")
        XCTAssertEqual(result?.brand, "Bell's")
        XCTAssertEqual(result?.style, .ipa)
        XCTAssertEqual(result?.abv, 7.0)
        XCTAssertEqual(result?.origin, "Michigan")
        XCTAssertNil(result?.explanation)
    }

    func testFactOnlyEnrichmentGetsLocalVerdictCopy() {
        let facts = Enrichment(name: "Bia Viet", style: .lager)

        let result = facts.addingLocalExplanation(for: .tryIt)

        XCTAssertEqual(result.name, "Bia Viet")
        XCTAssertEqual(result.explanation, "Looks like a Lager — that lines up with your taste.")
    }

    func testOlderScanLogEntryStillDecodesWithoutFoundationModelField() throws {
        let json = """
        [{"timestamp":0,"inputText":"Orion","resolvedName":"Orion","style":"Lager","source":"labelText","verdict":"YOUR_CALL","score":0,"latencyMs":20,"path":"image","deviceModel":"iPhone16,1","osVersion":"26.4","appBuild":"1.0 (84)"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let events = try decoder.decode([ScanEvent].self, from: Data(json.utf8))
        XCTAssertEqual(events.first?.resolvedName, "Orion")
        XCTAssertNil(events.first?.foundationModelsAvailable)
    }
}
