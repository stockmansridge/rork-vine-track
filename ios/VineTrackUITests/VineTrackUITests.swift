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
        let signIn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sign' OR label CONTAINS[c] 'Continue' OR label CONTAINS[c] 'Demo'")).firstMatch
        let anyTab = app.tabBars.firstMatch
        let anyNav = app.navigationBars.firstMatch
        let appeared = signIn.waitForExistence(timeout: 15)
            || anyTab.waitForExistence(timeout: 1)
            || anyNav.waitForExistence(timeout: 1)
        XCTAssertTrue(appeared, "Expected login, tab bar, or navigation bar to appear after launch")
    }

    @MainActor
    func testDemoModeEntryIfAvailable() throws {
        let app = XCUIApplication()
        app.launch()
        let demo = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Demo' OR label CONTAINS[c] 'Try'")).firstMatch
        if demo.waitForExistence(timeout: 10) {
            demo.tap()
            // Once in demo, we should see the tab bar or a navigation bar.
            let tab = app.tabBars.firstMatch
            let nav = app.navigationBars.firstMatch
            let reached = tab.waitForExistence(timeout: 10) || nav.waitForExistence(timeout: 5)
            XCTAssertTrue(reached, "Expected to reach the main app after demo entry")
        }
    }

    @MainActor
    func testTabBarContainsHomeIfSignedIn() throws {
        let app = XCUIApplication()
        app.launch()
        let tab = app.tabBars.firstMatch
        guard tab.waitForExistence(timeout: 10) else {
            // Not signed in yet — acceptable.
            return
        }
        // At least one tab button should be hittable.
        XCTAssertGreaterThan(tab.buttons.count, 0)
    }

    @MainActor
    func testOpenSettingsIfAvailable() throws {
        let app = XCUIApplication()
        app.launch()
        let tab = app.tabBars.firstMatch
        guard tab.waitForExistence(timeout: 10) else { return }
        let settingsButton = tab.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Settings' OR label CONTAINS[c] 'More'")).firstMatch
        if settingsButton.exists {
            settingsButton.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testOpenWorkTasksIfAvailable() throws {
        let app = XCUIApplication()
        app.launch()
        // Look for a work tasks entry anywhere reachable from home.
        let workLink = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Work Task'"))
            .firstMatch
        if workLink.waitForExistence(timeout: 10) && workLink.isHittable {
            workLink.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        }
    }
}
