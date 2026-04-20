import XCTest

final class VineTrackUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    @MainActor
    func testLoginScreenOrMainAppAppears() throws {
        let app = XCUIApplication()
        app.launch()
        // Either we see a sign-in affordance, a vineyards list, or the main tab bar.
        let signIn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sign' OR label CONTAINS[c] 'Continue' OR label CONTAINS[c] 'Demo'")).firstMatch
        let anyTab = app.tabBars.firstMatch
        let anyNav = app.navigationBars.firstMatch
        let appeared = signIn.waitForExistence(timeout: 15)
            || anyTab.waitForExistence(timeout: 1)
            || anyNav.waitForExistence(timeout: 1)
        XCTAssertTrue(appeared, "Expected login, tab bar, or navigation bar to appear after launch")
    }
}
