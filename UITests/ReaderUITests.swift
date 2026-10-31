import XCTest

final class ReaderUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--demo", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Segnali dal faro"].firstMatch.waitForExistence(timeout: 15))
        // A failed language-test run may have left an explicit override behind.
        if app.staticTexts["Read-only library"].exists {
            app.buttons["connection-settings"].tap()
            app.buttons["app-language"].tap()
            app.buttons["Italiano"].tap()
            app.buttons["Chiudi"].tap()
        }
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

    private func tapOption(_ identifier: String) {
        let option = app.buttons[identifier]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        let form = app.collectionViews["reader-options"]
        let scroller = form.exists ? form : app
        for _ in 0..<3 {
            if option.isHittable { break }
            scroller.swipeUp(velocity: .slow)
        }
        for _ in 0..<6 {
            if option.isHittable { break }
            scroller.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(option.isHittable, "Option must be visible: \(identifier)")
        option.tap()
    }

    private func setReadingOptions(direction: String = "automatic", layout: String = "automatic", axis: String = "automatic") {
        app.buttons["Opzioni di lettura"].tap()
        // A vertical flow intentionally disables the horizontal direction controls.
        tapOption("reader-axis-horizontal")
        tapOption("reader-direction-\(direction)")
        tapOption("reader-layout-\(layout)")
        tapOption("reader-axis-\(axis)")
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

    func testOfflineDownloadRelaunchProgressAndRemoval() {
        let id = "demo-lighthouse-volume-1"
        app.buttons["downloads"].tap()
        if app.buttons["remove-all-downloads"].exists {
            app.buttons["remove-all-downloads"].tap()
            app.buttons["confirm-remove-all-downloads"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Nessun download"].waitForExistence(timeout: 10))
        }
        app.buttons["Chiudi"].tap()
        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        openBook()
        setReadingOptions(direction: "ltr", layout: "paged", axis: "horizontal")
        returnToFirstDemoPage()
        app.buttons["Chiudi libro"].tap()
        app.buttons["download-\(id)"].tap()
        XCTAssertTrue(app.buttons["remove-download-\(id)"].waitForExistence(timeout: 30))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["downloads"].tap()
        XCTAssertTrue(app.staticTexts["Disponibile offline"].waitForExistence(timeout: 10))
        app.buttons["use-offline"].tap()
        XCTAssertTrue(app.staticTexts["Lettura offline"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["offline-book-\(id)"].tap()
        XCTAssertTrue(app.images["reader-page"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Segnalibro"].exists, "Offline reading must not promise a server bookmark write")
        app.buttons["Pagina successiva"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 10))
        // Closing waits for the local page save before checking a cold launch.
        sleep(1)
        app.buttons["Chiudi libro"].tap()
        app.terminate()
        // This debug-only mode disables generated demo pages: reads must come from disk.
        app.launchArguments += ["--offline-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Lettura offline"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["downloads"].tap()
        app.buttons["offline-book-\(id)"].tap()
        XCTAssertTrue(app.images["reader-page"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 10))
        app.buttons["Opzioni di lettura"].tap()
        tapOption("reader-layout-continuous")
        tapOption("reader-axis-vertical")
        app.buttons["Fine"].tap()
        XCTAssertTrue(app.collectionViews["reader-continuous"].waitForExistence(timeout: 10))
        app.buttons["Pagina successiva"].tap()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["reader-page"].firstMatch.waitForExistence(timeout: 10))
        capture("offline-download-reader")
        app.buttons["Chiudi libro"].tap()
        app.buttons["remove-all-downloads"].tap()
        app.buttons["confirm-remove-all-downloads"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Nessun download"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["offline-book-\(id)"].exists)
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

        setReadingOptions(direction: "rtl", layout: "continuous", axis: "vertical")
        let scroll = app.collectionViews["reader-continuous"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons["Pagina successiva"].frame.midX, app.buttons["Pagina precedente"].frame.midX,
                             "Vertical flow always advances down, regardless of saved horizontal direction")
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
        XCTAssertFalse(app.buttons["reader-direction-rtl"].isEnabled)
        XCTAssertEqual(app.buttons["reader-axis-vertical"].value as? String, "Selezionato")
        XCTAssertEqual(app.buttons["reader-layout-continuous"].value as? String, "Selezionato")
        tapOption("reader-layout-paged")
        app.buttons["Fine"].tap()
        waitForLoadedPage()
        XCTAssertFalse(scroll.exists)
        XCTAssertTrue(app.staticTexts["3 / 3"].exists, "Changing layout preserves the current page")
        setReadingOptions()
    }

    func testReadingAxesPagedGesturesAndHorizontalContinuous() {
        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        openBook()
        setReadingOptions(direction: "ltr", layout: "paged", axis: "vertical")
        returnToFirstDemoPage()
        app.images["reader-page"].firstMatch.swipeUp()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
        waitForLoadedPage()
        app.images["reader-page"].firstMatch.swipeDown()
        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 5))
        waitForLoadedPage()

        setReadingOptions(direction: "ltr", layout: "continuous", axis: "horizontal")
        let scroll = app.collectionViews["reader-continuous"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            if app.staticTexts["3 / 3"].exists { break }
            scroll.swipeLeft(velocity: .slow)
        }
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5), "LTR continuous advances with a left swipe")
        waitForLoadedPage()
        app.buttons["Pagina precedente"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
        waitForLoadedPage()
        setReadingOptions(direction: "rtl", layout: "continuous", axis: "horizontal")
        XCTAssertTrue(app.staticTexts["2 / 3"].exists, "Changing direction keeps the current page")
        XCTAssertLessThan(app.buttons["Pagina successiva"].frame.midX, app.buttons["Pagina precedente"].frame.midX)
        returnToFirstDemoPage()
        for _ in 0..<3 {
            if app.staticTexts["3 / 3"].exists { break }
            scroll.swipeRight(velocity: .slow)
        }
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5), "RTL continuous advances with a right swipe")
        waitForLoadedPage()
        capture("06-horizontal-continuous")
        app.buttons["Chiudi libro"].tap()
        openBook()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(scroll.exists)
        app.buttons["Opzioni di lettura"].tap()
        XCTAssertEqual(app.buttons["reader-axis-horizontal"].value as? String, "Selezionato")
        XCTAssertEqual(app.buttons["reader-direction-rtl"].value as? String, "Selezionato")
        app.buttons["Fine"].tap()
        setReadingOptions()
    }

    func testZAppLanguageChangesImmediatelyAndPersists() {
        app.buttons["connection-settings"].tap()
        app.buttons["app-language"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.staticTexts["App language"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Read-only library"].exists)
        XCTAssertTrue(app.staticTexts["Segnali dal faro"].firstMatch.exists, "Interface language never translates books")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Read-only library"].waitForExistence(timeout: 10), "Explicit language survives relaunch and overrides the Italian system language")
        app.buttons["connection-settings"].tap()
        app.buttons["app-language"].tap()
        app.buttons["System"].tap()
        XCTAssertTrue(app.staticTexts["Lingua dell’app"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["app-language"].tap()
        app.buttons["Italiano"].tap()
        capture("07-language-selection")
        app.buttons["Chiudi"].tap()
        XCTAssertTrue(app.staticTexts["Libreria in sola lettura"].exists)
        XCTAssertTrue(app.staticTexts["Demo sul dispositivo"].exists, "Changing language keeps the current connection")
    }
}
