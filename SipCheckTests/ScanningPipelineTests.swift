import XCTest
@testable import SipCheck

final class ScanningPipelineTests: XCTestCase {

    override func setUp() {
        super.setUp()
        OpenAIService.useMockResponses = true
    }

    override func tearDown() {
        OpenAIService.useMockResponses = false
        super.tearDown()
    }

    // MARK: - Mock Mode

    func testMockModeReturnsFixedResult() async throws {
        let pipeline = ScanningPipeline.shared
        let result = try await pipeline.scan(image: UIImage())

        XCTAssertEqual(result.scanSource, .mock, "Scan source should be .mock in mock mode")
    }

    // MARK: - Latency

    func testScanResultHasLatency() async throws {
        let pipeline = ScanningPipeline.shared
        let result = try await pipeline.scan(image: UIImage())

        XCTAssertGreaterThanOrEqual(result.latencyMs, 0, "Latency should be >= 0")
    }

    // MARK: - Mock Beer Info Fields

    func testMockBeerInfoFields() async throws {
        let pipeline = ScanningPipeline.shared
        let result = try await pipeline.scan(image: UIImage())

        XCTAssertEqual(result.beerInfo.name, "Mock IPA")
        XCTAssertEqual(result.beerInfo.brand, "Mock Brewery")
        XCTAssertEqual(result.beerInfo.style, .ipa)
        XCTAssertEqual(result.beerInfo.abv, 6.5)
    }
}
