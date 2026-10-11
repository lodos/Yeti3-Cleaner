import XCTest

final class LaunchTests: XCTestCase {
    // Catalyst presents TabView items as toolbar radio buttons.
    @MainActor private func selectTab(_ name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        if tab.exists { tab.tap() }
        else { app.radioButtons[name].tap() }
    }
    @MainActor func testAdPurchaseAndBackgroundSettingsAreReachable() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Без рекламы"].waitForExistence(timeout: 15))
        app.buttons["Без рекламы"].tap()
        XCTAssertTrue(app.staticTexts["Сеть без рекламы"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Восстановить покупки"].exists)
        app.buttons["Готово"].tap()
        selectTab("Настройки", in: app)
        for _ in 0..<14 {
            if app.switches["backgroundAnalysis"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.switches["backgroundAnalysis"].exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "06-Advanced-settings"; image.lifetime = .keepAlways; add(image)
    }
    @MainActor func testLargeTextAndLandscapeRemainNavigable() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["startScan"].waitForExistence(timeout: 15))
        let adButton = app.buttons["Без рекламы"]
        XCTAssertTrue(adButton.isHittable)
        XCTAssertLessThan(adButton.frame.maxY - app.frame.minY, app.frame.height * 0.35)
        let portrait = XCTAttachment(screenshot: app.screenshot()); portrait.name = "07-Large-text"; portrait.lifetime = .keepAlways; add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        selectTab("Настройки", in: app)
        XCTAssertTrue(app.buttons["strategyPicker"].waitForExistence(timeout: 5))
        let rotated = NSPredicate { _, _ in app.frame.width > app.frame.height }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: rotated, object: nil)], timeout: 10), .completed)
        XCTAssertTrue(adButton.isHittable)
        XCTAssertLessThan(adButton.frame.maxY - app.frame.minY, app.frame.height * 0.35)
        XCTAssertTrue(app.tabBars.buttons["Настройки"].isHittable)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); landscape.name = "08-Landscape-large-text"; landscape.lifetime = .keepAlways; add(landscape)
    }
    @MainActor func testStoreScreenshots() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["startScan"].waitForExistence(timeout:15))
        for (name, tab) in [("01-Overview", "Обзор"), ("02-Photos", "Фото"), ("03-Files", "Файлы"), ("04-Contacts", "Контакты"), ("05-Settings", "Настройки")] {
            selectTab(tab, in: app)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = name; image.lifetime = .keepAlways; add(image)
        }
    }
    @MainActor func testLaunchAndSettingsWithoutPermissionPrompts() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["startScan"].waitForExistence(timeout: 15))
        let screen = XCTAttachment(screenshot: app.screenshot()); screen.name = "Dashboard"; screen.lifetime = .keepAlways; add(screen)
        selectTab("Настройки", in: app)
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["strategyPicker"].exists)
        selectTab("Фото", in: app)
        XCTAssertTrue(app.navigationBars["Фото и видео"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Удалить выбранное"].exists)
        selectTab("Файлы", in: app)
        XCTAssertTrue(app.buttons["Выбрать файлы или папку…"].waitForExistence(timeout: 5))
        selectTab("Контакты", in: app)
        XCTAssertTrue(app.navigationBars["Контакты"].waitForExistence(timeout: 5))
    }
    @MainActor func testManualStrategyPersistsAndEmptyScanFinishes() throws {
        let app = XCUIApplication(); app.launch()
        selectTab("Настройки", in: app)
        app.buttons["strategyPicker"].tap()
        app.buttons["Ручная"].tap()
        app.terminate(); app.launch()
        selectTab("Настройки", in: app)
        XCTAssertTrue(app.buttons["strategyPicker"].label.contains("Ручная"))
        selectTab("Обзор", in: app)
        app.buttons["startScan"].tap()
        XCTAssertTrue(app.staticTexts["Анализ завершён. Ничего не удалено."].waitForExistence(timeout: 10))
        selectTab("Настройки", in: app)
        app.buttons["strategyPicker"].tap()
        app.buttons["Безопасная"].tap()
    }
}
