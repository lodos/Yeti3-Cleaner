import XCTest

final class LaunchTests: XCTestCase {
    @MainActor func testLaunchAndSettingsWithoutPermissionPrompts() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["startScan"].waitForExistence(timeout: 15))
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Dashboard"; screen.lifetime = .keepAlways; add(screen)
        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["strategyPicker"].exists)
        app.tabBars.buttons["Фото"].tap()
        XCTAssertTrue(app.navigationBars["Фото и видео"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Удалить выбранное"].exists)
        app.tabBars.buttons["Файлы"].tap()
        XCTAssertTrue(app.buttons["Выбрать файлы или папку…"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Контакты"].tap()
        XCTAssertTrue(app.navigationBars["Контакты"].waitForExistence(timeout: 5))
    }
    @MainActor func testManualStrategyPersistsAndEmptyScanFinishes() throws {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Настройки"].tap()
        app.buttons["strategyPicker"].tap()
        app.buttons["Ручная"].tap()
        app.terminate(); app.launch()
        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.buttons["strategyPicker"].label.contains("Ручная"))
        app.tabBars.buttons["Обзор"].tap()
        app.buttons["startScan"].tap()
        XCTAssertTrue(app.staticTexts["Анализ завершён. Ничего не удалено."].waitForExistence(timeout: 10))
        app.tabBars.buttons["Настройки"].tap()
        app.buttons["strategyPicker"].tap()
        app.buttons["Безопасная"].tap()
    }
}
