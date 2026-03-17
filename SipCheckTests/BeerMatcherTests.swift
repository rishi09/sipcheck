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
}
