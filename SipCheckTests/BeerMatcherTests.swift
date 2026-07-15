import XCTest
@testable import SipCheck

final class BeerMatcherTests: XCTestCase {

    // MARK: - Test Data

    private var testDrinks: [Drink] {
        [
            Drink(name: "Sierra Nevada Pale Ale", brand: "Sierra Nevada", style: "Pale Ale", rating: .like),
            Drink(name: "Blue Moon Belgian White", brand: "Blue Moon", style: "Wheat", rating: .neutral),
            Drink(name: "Guinness Draught", brand: "Guinness", style: "Stout", rating: .like),
            Drink(name: "Bud Light", brand: "Anheuser-Busch", style: "Light Lager", rating: .dislike),
        ]
    }

    // MARK: - Exact Match

    func testExactMatch() {
        let result = BeerMatcher.findMatch(for: "Sierra Nevada Pale Ale", in: testDrinks)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "Sierra Nevada Pale Ale")
    }

    func testExactMatchReturnsCorrectDrink() {
        let result = BeerMatcher.findMatch(for: "Guinness Draught", in: testDrinks)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.brand, "Guinness")
        XCTAssertEqual(result?.rating, .like)
    }

    // MARK: - Case Insensitive

    func testCaseInsensitiveMatch() {
        let result = BeerMatcher.findMatch(for: "sierra nevada pale ale", in: testDrinks)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "Sierra Nevada Pale Ale")
    }

    func testMixedCaseMatch() {
        let result = BeerMatcher.findMatch(for: "BLUE MOON BELGIAN WHITE", in: testDrinks)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "Blue Moon Belgian White")
    }

    // MARK: - Partial / Contains Match

    func testPartialMatchQueryContainedInName() {
        let result = BeerMatcher.findMatch(for: "Sierra Nevada", in: testDrinks)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "Sierra Nevada Pale Ale")
    }

    func testPartialMatchNameContainedInQuery() {
        let result = BeerMatcher.findMatch(for: "I had some Bud Light yesterday", in: testDrinks)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "Bud Light")
    }

    // MARK: - Fuzzy Match (Levenshtein)

    func testFuzzyMatchWithTypo() {
        let result = BeerMatcher.findMatch(for: "Siera Nevada Pale Ale", in: testDrinks)
        XCTAssertNotNil(result, "Should match despite typo in 'Sierra'")
        XCTAssertEqual(result?.name, "Sierra Nevada Pale Ale")
    }

    // MARK: - No Match

    func testNoMatch() {
        let result = BeerMatcher.findMatch(for: "Heineken", in: testDrinks)
        XCTAssertNil(result)
    }

    func testNoMatchWithCompletelyDifferentText() {
        let result = BeerMatcher.findMatch(for: "Pizza Margherita", in: testDrinks)
        XCTAssertNil(result)
    }

    // MARK: - Edge Cases

    func testEmptyHistory() {
        let result = BeerMatcher.findMatch(for: "Any Beer", in: [])
        XCTAssertNil(result)
    }

    func testEmptyQuery() {
        let result = BeerMatcher.findMatch(for: "", in: testDrinks)
        // Empty query should not crash — behavior may vary
        // Just verify it doesn't crash
        _ = result
    }

    func testWhitespaceQuery() {
        let result = BeerMatcher.findMatch(for: "  Sierra Nevada Pale Ale  ", in: testDrinks)
        XCTAssertNotNil(result, "Should handle leading/trailing whitespace")
    }

    func testGenericStyleNameDoesNotClaimAnUnrelatedBeer() {
        let drinks = [Drink(name: "Hazy Little Thing IPA", style: "IPA", rating: .like)]
        XCTAssertNil(BeerMatcher.findMatch(for: "IPA", in: drinks))
    }

    func testFuzzyMatchingReturnsClosestDrinkInsteadOfFirstAboveThreshold() {
        let drinks = [
            Drink(name: "Sierra Nevada Torpedo", style: "IPA", rating: .like),
            Drink(name: "Sierra Nevada Pale Ale", style: "Pale Ale", rating: .like)
        ]
        let result = BeerMatcher.findMatch(for: "Siera Nevada Pale Ale", in: drinks)
        XCTAssertEqual(result?.name, "Sierra Nevada Pale Ale")
    }

    func testPunctuationDifferencesNormalizeForExactIdentity() {
        let drinks = [Drink(name: "Bell's Two Hearted", style: "IPA", rating: .like)]
        let result = BeerMatcher.findMatch(for: "Bells Two Hearted", in: drinks)
        XCTAssertEqual(result?.name, "Bell's Two Hearted")
    }

    func testLongOCRBlobStillFindsContainedHistoryName() {
        let drinks = [Drink(name: "Two Hearted", style: "IPA", rating: .like)]
        let legalCopy = String(repeating: " government warning", count: 20)
        let result = BeerMatcher.findMatch(for: "Bell's Two Hearted IPA\(legalCopy)", in: drinks)
        XCTAssertEqual(result?.name, "Two Hearted")
    }
}
