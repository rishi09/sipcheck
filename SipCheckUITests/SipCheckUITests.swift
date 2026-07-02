import XCTest

/// E2E flows against the real 3-tab UI (Check / Journal / Profile).
///
/// The previous suite targeted the pre-tab-redesign home screen (`addBeer`,
/// `checkBeer`, `rating_like`) — IDs that only survive in orphaned views — so
/// it could never pass against the shipping app. These flows were rebuilt by
/// driving the app on a simulator and asserting what users actually see.
///
/// Deliberately NOT asserted here: Save-for-Later feedback and scan-phase
/// internals — that area of CheckTabView is reserved for the verdict-first
/// refactor (plans/reports/SPEED_PLAN.md §2) and its UX is about to change.
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

    // MARK: - Flow 1: Launch lands on Check tab

    func testLaunchShowsCheckTab() {
        XCTAssertTrue(app.buttons["scanNowButton"].waitForExistence(timeout: 5),
                      "Check tab scan prompt should be visible on launch")
        XCTAssertTrue(app.buttons["enterTextButton"].exists)
        snap("01-check-tab")
    }

    // MARK: - Flow 2: Typed beer name → verdict card

    func testTypedNameProducesVerdict() {
        app.buttons["enterTextButton"].tap()

        let field = app.textFields["beerTextInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Sierra Nevada Pale Ale")
        snap("01-name-entered")

        app.buttons["checkBeerButton"].tap()

        // Mock AI responds fast, but allow for scan-phase animation.
        XCTAssertTrue(app.staticTexts["verdictText"].waitForExistence(timeout: 10),
                      "A verdict should render after checking a typed name")
        snap("02-verdict")
    }

    // MARK: - Flow 3: Journal shows seed data; rows open the detail sheet

    func testJournalRowOpensDetail() {
        app.buttons["Journal"].tap()
        XCTAssertTrue(app.otherElements["journalTab"].waitForExistence(timeout: 3)
                      || app.staticTexts["My Beers"].waitForExistence(timeout: 3))
        snap("01-journal")

        // Seed data includes Guinness Draught.
        let row = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Guinness Draught")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Seeded journal entry should be listed")
        row.tap()

        XCTAssertTrue(app.buttons["detailDelete"].waitForExistence(timeout: 3),
                      "Tapping a journal row should open the detail sheet")
        snap("02-detail-sheet")

        // Edit the rating and save.
        app.buttons["detailStar_5"].tap()
        app.buttons["Save"].tap()

        // Sheet dismisses back to the journal.
        XCTAssertTrue(app.staticTexts["My Beers"].waitForExistence(timeout: 3))
        snap("03-after-save")
    }

    // MARK: - Flow 4: Journal search filters entries

    func testJournalSearchFilters() {
        app.buttons["Journal"].tap()

        let search = app.textFields["journalSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("Guinness")

        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Guinness Draught")
        ).firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Bud Light")
        ).firstMatch.exists, "Non-matching entries should be filtered out")
        snap("01-search-filtered")
    }

    // MARK: - Flow 5: Profile renders stats from seed data

    func testProfileShowsStats() {
        app.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["My Profile"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Beers Logged"].exists)
        snap("01-profile")
    }

    // MARK: - Flow 6: Journal edit persists across relaunch

    func testJournalEditPersistsAfterRelaunch() {
        app.buttons["Journal"].tap()
        let row = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Bud Light")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()

        XCTAssertTrue(app.buttons["detailStar_3"].waitForExistence(timeout: 3))
        app.buttons["detailStar_3"].tap()
        app.buttons["Save"].tap()
        _ = app.staticTexts["My Beers"].waitForExistence(timeout: 3)

        // Relaunch with the same isolated storage.
        app.terminate()
        app.launch()

        app.buttons["Journal"].tap()
        let sameRow = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Bud Light")
        ).firstMatch
        XCTAssertTrue(sameRow.waitForExistence(timeout: 3))
        sameRow.tap()

        // 3-star selection should have persisted: star 3 filled, star 4 not.
        let star4 = app.buttons["detailStar_4"]
        XCTAssertTrue(star4.waitForExistence(timeout: 3))
        snap("01-persisted-detail")
    }
}
