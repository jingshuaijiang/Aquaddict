import XCTest

// Walks the app on a fresh simulator (demo data showing) and captures the
// App Store screenshot set. Export with:
//   xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shoot(_ name: String) {
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    func testScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        let ok = app.buttons["I understand"]
        if ok.waitForExistence(timeout: 5) { ok.tap() }
        sleep(4)                                  // parse + chart render
        shoot("01-home")

        app.tabBars.buttons["Map"].tap()
        sleep(5)                                  // map tiles
        shoot("02-map")

        app.tabBars.buttons["Log"].tap()
        sleep(1)
        let row = app.staticTexts["#2"].firstMatch
        if row.waitForExistence(timeout: 3) {
            row.tap()
            sleep(2)
            shoot("03-dive")
            app.swipeUp()
            app.swipeUp()
            sleep(1)
            shoot("04-dive-tech")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        let training = app.staticTexts["GUE Training"].firstMatch
        if training.waitForExistence(timeout: 3) {
            training.tap()
            sleep(2)
            shoot("05-training")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
    }
}
