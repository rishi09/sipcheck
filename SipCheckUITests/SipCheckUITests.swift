import XCTest

final class SipCheckUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launchArguments = ["--mock-ai", "--seed-data", "--isolated-storage"]
        app.launch()
    }

    /// Attach a named screenshot to the test report (kept even on pass) so CI
    /// can export step-by-step images of each flow.
    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Flow 1: Add Beer Manually

    func testAddBeerManually() {
        snap("01-home")

        // Tap Add Beer
        app.buttons["addBeer"].tap()

        // Fill in beer name
        let nameField = app.textFields["beerName"]
        nameField.tap()
        nameField.typeText("Test Hazy IPA")

        // Fill in brewery
        let breweryField = app.textFields["breweryName"]
        breweryField.tap()
        breweryField.typeText("Test Brewery")

        // Tap thumbs up rating
        app.buttons["rating_like"].tap()
        snap("02-form-filled")

        // Save
        app.buttons["saveBeer"].tap()

        // Verify we're back at home and beer appears in recent list
        XCTAssertTrue(app.staticTexts["Test Hazy IPA"].waitForExistence(timeout: 2))
        snap("03-saved-on-home")
    }

    // MARK: - Flow 2: Check Beer Found

    func testCheckBeerFound() {
        // Seed data includes "Sierra Nevada Pale Ale"
        app.buttons["checkBeer"].tap()

        let searchField = app.textFields["searchField"]
        searchField.tap()
        searchField.typeText("Sierra Nevada Pale Ale")

        app.buttons["searchButton"].tap()

        // Wait for mock AI response
        let triedText = app.staticTexts["You've tried this!"]
        XCTAssertTrue(triedText.waitForExistence(timeout: 5))
        snap("01-result-found")
    }

    // MARK: - Flow 3: Check Beer Not Found + Add

    func testCheckBeerNotFoundAndAdd() {
        app.buttons["checkBeer"].tap()

        let searchField = app.textFields["searchField"]
        searchField.tap()
        searchField.typeText("Phantom Ale")

        app.buttons["searchButton"].tap()

        // Wait for "Haven't tried yet"
        let notTriedText = app.staticTexts["Haven't tried yet"]
        XCTAssertTrue(notTriedText.waitForExistence(timeout: 5))
        snap("01-result-not-found")

        // Add to my beers
        app.buttons["Add to my beers"].tap()

        // Should dismiss — verify we're back at home
        XCTAssertTrue(app.staticTexts["SipCheck"].waitForExistence(timeout: 2))
        snap("02-added-back-home")
    }

    // MARK: - Flow 4: View Beer List

    func testViewBeerList() {
        // Seed data should show recent beers — tap "See All Beers"
        let seeAll = app.buttons["See All Beers"]
        if seeAll.waitForExistence(timeout: 2) {
            seeAll.tap()
            // Should see the list view with seed data
            XCTAssertTrue(app.navigationBars["All Beers"].waitForExistence(timeout: 2))
            snap("01-beer-list")
        }
    }

    // MARK: - Flow 5: Data Persists After Relaunch

    func testDataPersistsAfterRelaunch() {
        // Add a beer
        app.buttons["addBeer"].tap()
        let nameField = app.textFields["beerName"]
        nameField.tap()
        nameField.typeText("Persistence Test Beer")
        app.buttons["saveBeer"].tap()

        // Wait for save
        _ = app.staticTexts["Persistence Test Beer"].waitForExistence(timeout: 2)

        // Relaunch (same launch args = same isolated storage path)
        app.terminate()
        app.launch()

        // Verify beer still exists
        XCTAssertTrue(app.staticTexts["Persistence Test Beer"].waitForExistence(timeout: 3),
                      "Beer should persist after relaunch")
        snap("01-after-relaunch")
    }
}
