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
}
