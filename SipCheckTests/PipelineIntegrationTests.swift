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
}
