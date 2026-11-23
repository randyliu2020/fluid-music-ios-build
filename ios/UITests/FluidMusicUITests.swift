import XCTest

final class FluidMusicUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["song-晨光"].waitForExistence(timeout: 30))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testPlaybackLyricsQueueAndFavorites() throws {
        let app = launch()
        capture(app, "01-library")
        app.buttons["song-晨光"].tap()
        XCTAssertTrue(app.buttons["openPlayer"].waitForExistence(timeout: 10))
        app.buttons["openPlayer"].tap()
        XCTAssertTrue(app.staticTexts["playerTitle"].waitForExistence(timeout: 5))
        capture(app, "02-player")
        app.buttons["favoriteTrack"].tap()
        app.buttons["toggleLyrics"].tap()
        capture(app, "03-lyrics")
        app.buttons["openQueue"].tap()
        XCTAssertTrue(app.navigationBars.containing(.staticText, identifier: "播放队列 · 3").firstMatch.waitForExistence(timeout: 5))
        capture(app, "04-queue")
        app.buttons["完成"].firstMatch.tap()
        app.buttons["closePlayer"].tap()
        app.tabBars.buttons["喜欢"].tap()
        XCTAssertTrue(app.buttons["song-晨光"].waitForExistence(timeout: 5))
        capture(app, "05-favorites")
    }
    @MainActor func testRestoresPausedPlayerAfterRelaunch() throws {
        let app = launch()
        app.buttons["song-微风"].tap()
        XCTAssertTrue(app.buttons["miniPlayPause"].waitForExistence(timeout: 5))
        app.buttons["miniPlayPause"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["openPlayer"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["miniPlayPause"].label, "播放")
        app.buttons["openPlayer"].tap()
        XCTAssertEqual(app.staticTexts["playerTitle"].label, "微风")
        capture(app, "06-restored")
    }
    @MainActor func testSettingsAndEqualizer() throws {
        let app = launch()
        app.tabBars.buttons["设置"].tap()
        app.buttons["均衡器"].tap()
        XCTAssertTrue(app.switches["启用均衡器"].waitForExistence(timeout: 5))
        app.switches["启用均衡器"].tap()
        capture(app, "07-equalizer")
    }
}
