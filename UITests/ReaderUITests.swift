import XCTest

final class ReaderUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--demo", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Segnali dal faro"].firstMatch.waitForExistence(timeout: 15))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openBook() {
        let book = app.staticTexts["Volume 1"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        waitForLoadedPage()
    }

    private func waitForLoadedPage() {
        XCTAssertTrue(app.images["reader-page"].firstMatch.waitForExistence(timeout: 10))
        // The page counter changes before decoding and local progress saving finish.
        let ready = NSPredicate(format: "exists == true AND isEnabled == true")
        expectation(for: ready, evaluatedWith: app.buttons["Segnalibro"])
        waitForExpectations(timeout: 10)
    }

    private func returnToFirstDemoPage() {
        waitForLoadedPage()
        // Use discrete controls: a normalized slider drag can miss its endpoint
        // on iPad, especially when an earlier test left the book at its last page.
        let previous = app.buttons["Pagina precedente"]
        for _ in 0..<2 {
            guard previous.isEnabled else { break }
            previous.tap()
            waitForLoadedPage()
        }
        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 5))
    }

    private func setReadingOptions(direction: String = "automatic", layout: String = "automatic") {
        app.buttons["Opzioni di lettura"].tap()
        let directionOption = app.buttons["reader-direction-\(direction)"]
        XCTAssertTrue(directionOption.waitForExistence(timeout: 5))
        directionOption.tap()
        app.buttons["reader-layout-\(layout)"].tap()
        app.buttons["Fine"].tap()
        waitForLoadedPage()
    }

    func testDemoReadingProgressAndScreenshots() {
        XCTAssertTrue(app.staticTexts["Libreria in sola lettura"].exists)
        XCTAssertTrue(app.staticTexts["Demo sul dispositivo"].exists)
        capture("01-library")

        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Disponibili da leggere"].waitForExistence(timeout: 10))
        capture("02-books")
        openBook()
        setReadingOptions()
        // Also make re-runs deterministic without modifying stored files directly.
        returnToFirstDemoPage()
        capture("03-reader")
        app.buttons["Pagina successiva"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
        waitForLoadedPage()
        app.buttons["Chiudi libro"].tap()
        openBook()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5), "Reading position survives closing the book")
        app.buttons["Chiudi libro"].tap()
        app.navigationBars.buttons.firstMatch.tap()

        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Atlante")
        XCTAssertTrue(app.staticTexts["Atlante delle nuvole"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Segnali dal faro"].exists)
        app.staticTexts["Atlante delle nuvole"].firstMatch.tap()
        openBook()
        setReadingOptions()
        XCTAssertTrue(app.collectionViews["reader-continuous"].exists, "Webtoon defaults to continuous scrolling")
        returnToFirstDemoPage()
        capture("04-webtoon")
        app.buttons["Pagina successiva"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
    }

    func testDemoBookmarkLifecycleAndIndependentLocalResume() {
        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        openBook()
        setReadingOptions()
        returnToFirstDemoPage()
        let bookmarkMenu = app.buttons["Segnalibro"]
        XCTAssertTrue(bookmarkMenu.waitForExistence(timeout: 5))
        // Wait until the displayed image is loaded and the menu becomes enabled.
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: bookmarkMenu)
        waitForExpectations(timeout: 10)
        bookmarkMenu.tap()
        if app.buttons["Rimuovi segnalibro"].exists {
            app.buttons["Rimuovi segnalibro"].tap()
            bookmarkMenu.tap()
        }
        app.buttons["Salva segnalibro"].tap()
        XCTAssertTrue(app.staticTexts["Segnalibro a pagina 1"].waitForExistence(timeout: 5))
        app.buttons["Pagina successiva"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
        expectation(for: enabled, evaluatedWith: bookmarkMenu)
        waitForExpectations(timeout: 10)
        bookmarkMenu.tap()
        app.buttons["Sposta segnalibro a questa pagina"].tap()
        XCTAssertTrue(app.staticTexts["Segnalibro a pagina 2"].waitForExistence(timeout: 5))
        app.buttons["Pagina successiva"].tap()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5))
        expectation(for: enabled, evaluatedWith: bookmarkMenu)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["Segnalibro a pagina 2"].exists, "Page turns only update local resume")
        app.buttons["Chiudi libro"].tap()
        openBook()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5))
        app.buttons["Chiudi libro"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Segnalibri"].tap()
        let saved = app.buttons["bookmark-demo-lighthouse"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5), "Bookmark list opens the explicitly saved page")
        expectation(for: enabled, evaluatedWith: bookmarkMenu)
        waitForExpectations(timeout: 10)
        bookmarkMenu.tap()
        app.buttons["Rimuovi segnalibro"].tap()
        app.buttons["Pagina successiva"].tap()
        expectation(for: enabled, evaluatedWith: bookmarkMenu)
        waitForExpectations(timeout: 10)
        app.buttons["Chiudi libro"].tap()
        XCTAssertFalse(saved.exists, "A removed bookmark is not restored by further reading")
    }

    func testReadingDirectionContinuousScrollAndRememberedOptions() {
        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        openBook()
        setReadingOptions(direction: "ltr", layout: "paged")
        returnToFirstDemoPage()
        XCTAssertGreaterThan(app.buttons["Pagina successiva"].frame.midX, app.buttons["Pagina precedente"].frame.midX)

        setReadingOptions(direction: "rtl", layout: "continuous")
        let scroll = app.collectionViews["reader-continuous"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.buttons["Pagina successiva"].frame.midX, app.buttons["Pagina precedente"].frame.midX)
        app.buttons["Pagina successiva"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
        waitForLoadedPage()
        for _ in 0..<3 {
            if app.staticTexts["3 / 3"].exists { break }
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5), "Scrolling changes the current page without paging buttons")
        waitForLoadedPage()
        capture("05-continuous-reader")
        app.buttons["Segnalibro"].tap()
        let move = app.buttons["Sposta segnalibro a questa pagina"]
        if move.exists { move.tap() } else { app.buttons["Salva segnalibro"].tap() }
        XCTAssertTrue(app.staticTexts["Segnalibro a pagina 3"].waitForExistence(timeout: 5), "Continuous bookmarks use the visible loaded page")
        app.buttons["Segnalibro"].tap()
        app.buttons["Rimuovi segnalibro"].tap()

        app.buttons["Chiudi libro"].tap()
        openBook()
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "Layout survives closing the volume")
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5), "Continuous reader resumes the visible loaded page")
        app.buttons["Opzioni di lettura"].tap()
        XCTAssertEqual(app.buttons["reader-direction-rtl"].value as? String, "Selezionato")
        XCTAssertEqual(app.buttons["reader-layout-continuous"].value as? String, "Selezionato")
        app.buttons["reader-layout-paged"].tap()
        app.buttons["Fine"].tap()
        waitForLoadedPage()
        XCTAssertFalse(scroll.exists)
        XCTAssertTrue(app.staticTexts["3 / 3"].exists, "Changing layout preserves the current page")
        setReadingOptions()
    }
}
