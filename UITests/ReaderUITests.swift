import XCTest

final class ReaderUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--demo", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT", "-app.language.v2", "english"]
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
        expectation(for: ready, evaluatedWith: app.buttons["Bookmark"])
        waitForExpectations(timeout: 10)
    }

    private func returnToFirstDemoPage() {
        waitForLoadedPage()
        // Use discrete controls: a normalized slider drag can miss its endpoint
        // on iPad, especially when an earlier test left the book at its last page.
        let previous = app.buttons["Previous page"]
        for _ in 0..<2 {
            guard !app.staticTexts["1 / 3"].exists else { break }
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
        app.buttons["Reading options"].tap()
        // A vertical flow intentionally disables the horizontal direction controls.
        tapOption("reader-axis-horizontal")
        tapOption("reader-direction-\(direction)")
        tapOption("reader-layout-\(layout)")
        tapOption("reader-axis-\(axis)")
        app.buttons["Done"].tap()
        waitForLoadedPage()
    }

    func testDemoReadingProgressAndScreenshots() {
        XCTAssertTrue(app.staticTexts["Read-only library"].exists)
        XCTAssertTrue(app.staticTexts["On-device demo"].exists)
        capture("01-library")

        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Available to read"].waitForExistence(timeout: 10))
        capture("02-books")
        openBook()
        setReadingOptions()
        // Also make re-runs deterministic without modifying stored files directly.
        returnToFirstDemoPage()
        capture("03-reader")
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
        waitForLoadedPage()
        app.buttons["Close book"].tap()
        openBook()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5), "Reading position survives closing the book")
        app.buttons["Close book"].tap()
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
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
    }

    func testFollowedSeriesFilterAndPersistence() {
        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        let button = app.buttons["series-follow"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        if button.value as? String == "On" { button.tap() }
        button.tap()
        XCTAssertEqual(button.value as? String, "On")
        app.terminate(); app.launch()
        let filter = app.buttons["followed-series-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        XCTAssertTrue(app.staticTexts["Segnali dal faro"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Atlante delle nuvole"].firstMatch.exists)
        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        let followed = app.buttons["series-follow"]
        XCTAssertTrue(followed.waitForExistence(timeout: 10))
        XCTAssertEqual(followed.value as? String, "On")
        followed.tap()
        XCTAssertEqual(followed.value as? String, "Off")
    }

    func testSliderFollowsHorizontalDirectionAndVerticalStartsFromLeft() {
        app.staticTexts["Segnali dal faro"].firstMatch.tap(); openBook()
        for (direction, axis) in [("rtl", "horizontal"), ("ltr", "horizontal"), ("rtl", "vertical")] {
            setReadingOptions(direction: direction, layout: "paged", axis: axis)
            returnToFirstDemoPage()
            let slider = app.sliders["reader-page-slider"]
            let inset = 20 / slider.frame.width // thumb centre, also on wide iPads
            let firstX = direction == "rtl" && axis == "horizontal" ? 1 - inset : inset
            let lastX = 1 - firstX
            let first = slider.coordinate(withNormalizedOffset: CGVector(dx: firstX, dy: 0.5))
            let last = slider.coordinate(withNormalizedOffset: CGVector(dx: lastX, dy: 0.5))
            let windowWidth = app.windows.firstMatch.frame.width
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways; add(screenshot)
            first.press(forDuration: 0.1, thenDragTo: last)
            XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertEqual(app.windows.firstMatch.frame.width, windowWidth, accuracy: 1,
                "Dragging the page slider must not resize the iPad window")
            waitForLoadedPage()
            last.press(forDuration: 0.1, thenDragTo: first)
            XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 5))
            waitForLoadedPage()
        }
        setReadingOptions()
    }

    func testOfflineDownloadRelaunchProgressAndRemoval() {
        let id = "demo-lighthouse-volume-1"
        app.buttons["downloads"].tap()
        if app.buttons["remove-all-downloads"].exists {
            app.buttons["remove-all-downloads"].tap()
            app.buttons["confirm-remove-all-downloads"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["No downloads"].waitForExistence(timeout: 10))
        }
        app.buttons["Close"].tap()
        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        openBook()
        setReadingOptions(direction: "ltr", layout: "paged", axis: "horizontal")
        returnToFirstDemoPage()
        app.buttons["Close book"].tap()
        app.buttons["download-\(id)"].tap()
        XCTAssertTrue(app.buttons["remove-download-\(id)"].waitForExistence(timeout: 30))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["downloads"].tap()
        XCTAssertTrue(app.staticTexts["Available offline"].waitForExistence(timeout: 10))
        app.buttons["use-offline"].tap()
        XCTAssertTrue(app.staticTexts["Offline reading"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["offline-book-\(id)"].tap()
        XCTAssertTrue(app.images["reader-page"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Bookmark"].exists, "Demo bookmarks can also be changed offline and stay local")
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 10))
        // Closing waits for the local page save before checking a cold launch.
        sleep(1)
        app.buttons["Close book"].tap()
        app.terminate()
        // This debug-only mode disables generated demo pages: reads must come from disk.
        app.launchArguments += ["--offline-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Offline reading"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["downloads"].tap()
        app.buttons["offline-book-\(id)"].tap()
        XCTAssertTrue(app.images["reader-page"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 10))
        app.buttons["Reading options"].tap()
        tapOption("reader-layout-continuous")
        tapOption("reader-axis-vertical")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.collectionViews["reader-continuous"].waitForExistence(timeout: 10))
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["reader-page"].firstMatch.waitForExistence(timeout: 10))
        capture("offline-download-reader")
        app.buttons["Close book"].tap()
        app.buttons["remove-all-downloads"].tap()
        app.buttons["confirm-remove-all-downloads"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No downloads"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["offline-book-\(id)"].exists)
    }

    func testOfflineFilterBookmarksRangesAndSeriesNavigation() {
        let id = "demo-lighthouse-volume-1"
        app.buttons["downloads"].tap()
        if app.buttons["remove-all-downloads"].exists {
            app.buttons["remove-all-downloads"].tap()
            app.buttons["confirm-remove-all-downloads"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["No downloads"].waitForExistence(timeout: 10))
        }
        app.buttons["Close"].tap()
        // Keep an online bookmark in an undownloaded series: offline must hide it.
        for title in ["Il giardino sospeso", "Segnali dal faro"] {
            app.staticTexts[title].firstMatch.tap()
            openBook()
            app.buttons["Bookmark"].tap()
            let save = app.buttons["Save bookmark"]
            if save.exists { save.tap() } else { app.buttons["Move bookmark to this page"].tap() }
            app.buttons["reader-show-series"].tap()
            XCTAssertTrue(app.buttons["series-downloads"].waitForExistence(timeout: 10))
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        app.buttons["series-downloads"].tap()
        app.buttons["download-range"].tap()
        XCTAssertTrue(app.buttons["download-range-from"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["download-range-through"].exists)
        app.buttons["confirm-download-range"].tap()
        XCTAssertTrue(app.buttons["remove-download-\(id)"].waitForExistence(timeout: 30))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["offline-mode"].tap()
        XCTAssertTrue(app.staticTexts["Offline reading"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Segnali dal faro"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Il giardino sospeso"].exists)
        XCTAssertFalse(app.staticTexts["Atlante delle nuvole"].exists)
        app.buttons["followed-series-filter"].tap()
        XCTAssertTrue(app.staticTexts["Followed series are unavailable offline"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Segnali dal faro"].exists, "Offline follow list is empty even for a downloaded series")
        app.buttons["followed-series-filter"].tap()
        app.buttons["Bookmarks"].tap()
        XCTAssertTrue(app.buttons["bookmark-demo-lighthouse"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["bookmark-demo-garden"].exists)
        capture("offline-library-bookmarks")
        app.buttons["bookmark-demo-lighthouse"].tap()
        XCTAssertTrue(app.images["reader-page"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["reader-show-series"].tap()
        XCTAssertTrue(app.buttons["series-downloads"].waitForExistence(timeout: 10), "Return crosses bookmark sheet to series")
        app.buttons["series-downloads"].tap()
        app.buttons["remove-series-downloads"].tap()
        app.buttons["confirm-remove-series-downloads"].firstMatch.tap()
        XCTAssertFalse(app.buttons["remove-download-\(id)"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No downloads"].waitForExistence(timeout: 10))
        app.buttons["offline-mode"].tap()
        XCTAssertTrue(app.staticTexts["Il giardino sospeso"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        app.buttons["series-downloads"].tap()
        app.buttons["download-from-bookmark"].tap()
        XCTAssertTrue(app.buttons["remove-download-\(id)"].waitForExistence(timeout: 30))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["downloads"].tap()
        app.buttons["offline-book-\(id)"].tap()
        XCTAssertTrue(app.images["reader-page"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["reader-show-series"].tap()
        XCTAssertTrue(app.buttons["series-downloads"].waitForExistence(timeout: 10), "Return crosses download sheet to series")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["downloads"].tap()
        XCTAssertTrue(app.buttons["remove-all-downloads"].isHittable, "Delete all stays in the top toolbar")
        app.buttons["remove-all-downloads"].tap()
        app.buttons["confirm-remove-all-downloads"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No downloads"].waitForExistence(timeout: 10))
    }

    func testLibraryCoverFramesStayAlignedAcrossDifferentTitleLengths() {
        let first = app.descendants(matching: .any).matching(identifier: "cover-demo-lighthouse").firstMatch
        let second = app.descendants(matching: .any).matching(identifier: "cover-demo-garden").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10)); XCTAssertTrue(second.exists)
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 1, "Titles must not vertically center different cells")
        XCTAssertEqual(first.frame.height, second.frame.height, accuracy: 1)
        // SwiftUI exposes the enclosing navigation link's accessibility frame,
        // including its title. Matching row tops/heights catches the regression.
        capture("aligned-library-covers")
    }

    func testDemoBookmarkLifecycleAndIndependentLocalResume() {
        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        openBook()
        setReadingOptions()
        returnToFirstDemoPage()
        let bookmarkMenu = app.buttons["Bookmark"]
        XCTAssertTrue(bookmarkMenu.waitForExistence(timeout: 5))
        // Wait until the displayed image is loaded and the menu becomes enabled.
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: bookmarkMenu)
        waitForExpectations(timeout: 10)
        bookmarkMenu.tap()
        if app.buttons["Remove bookmark"].exists {
            app.buttons["Remove bookmark"].tap()
            bookmarkMenu.tap()
        }
        app.buttons["Save bookmark"].tap()
        XCTAssertTrue(app.staticTexts["Segnalibro a pagina 1"].waitForExistence(timeout: 5))
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
        expectation(for: enabled, evaluatedWith: bookmarkMenu)
        waitForExpectations(timeout: 10)
        bookmarkMenu.tap()
        app.buttons["Move bookmark to this page"].tap()
        XCTAssertTrue(app.staticTexts["Segnalibro a pagina 2"].waitForExistence(timeout: 5))
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5))
        expectation(for: enabled, evaluatedWith: bookmarkMenu)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["Segnalibro a pagina 2"].exists, "Page turns only update local resume")
        app.buttons["Close book"].tap()
        openBook()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5))
        app.buttons["Close book"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Bookmarks"].tap()
        let saved = app.buttons["bookmark-demo-lighthouse"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5), "Bookmark list opens the explicitly saved page")
        expectation(for: enabled, evaluatedWith: bookmarkMenu)
        waitForExpectations(timeout: 10)
        bookmarkMenu.tap()
        app.buttons["Remove bookmark"].tap()
        app.buttons["Next page"].tap()
        expectation(for: enabled, evaluatedWith: bookmarkMenu)
        waitForExpectations(timeout: 10)
        app.buttons["Close book"].tap()
        XCTAssertFalse(saved.exists, "A removed bookmark is not restored by further reading")
    }

    func testReadingDirectionContinuousScrollAndRememberedOptions() {
        app.staticTexts["Segnali dal faro"].firstMatch.tap()
        openBook()
        setReadingOptions(direction: "ltr", layout: "paged")
        returnToFirstDemoPage()
        XCTAssertGreaterThan(app.buttons["Next page"].frame.midX, app.buttons["Previous page"].frame.midX)

        setReadingOptions(direction: "rtl", layout: "continuous", axis: "vertical")
        let scroll = app.collectionViews["reader-continuous"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons["Next page"].frame.midX, app.buttons["Previous page"].frame.midX,
                             "Vertical flow always advances down, regardless of saved horizontal direction")
        app.buttons["Next page"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
        waitForLoadedPage()
        for _ in 0..<3 {
            if app.staticTexts["3 / 3"].exists { break }
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5), "Scrolling changes the current page without paging buttons")
        waitForLoadedPage()
        capture("05-continuous-reader")
        app.buttons["Bookmark"].tap()
        let move = app.buttons["Move bookmark to this page"]
        if move.exists { move.tap() } else { app.buttons["Save bookmark"].tap() }
        XCTAssertTrue(app.staticTexts["Segnalibro a pagina 3"].waitForExistence(timeout: 5), "Continuous bookmarks use the visible loaded page")
        app.buttons["Bookmark"].tap()
        app.buttons["Remove bookmark"].tap()

        // Only a deliberate extra pull at the end opens chapter navigation;
        // this demo has no next chapter, so the page must remain available.
        for _ in 0..<3 {
            if app.alerts["Chapter navigation"].exists { break }
            scroll.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(app.alerts.staticTexts["There is no next chapter."].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()

        app.buttons["Close book"].tap()
        openBook()
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "Layout survives closing the volume")
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5), "Continuous reader resumes the visible loaded page")
        app.buttons["Reading options"].tap()
        XCTAssertEqual(app.buttons["reader-direction-rtl"].value as? String, "Selected")
        XCTAssertFalse(app.buttons["reader-direction-rtl"].isEnabled)
        XCTAssertEqual(app.buttons["reader-axis-vertical"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["reader-layout-continuous"].value as? String, "Selected")
        tapOption("reader-layout-paged")
        app.buttons["Done"].tap()
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
        app.buttons["Previous page"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
        waitForLoadedPage()
        setReadingOptions(direction: "rtl", layout: "continuous", axis: "horizontal")
        XCTAssertTrue(app.staticTexts["2 / 3"].exists, "Changing direction keeps the current page")
        XCTAssertLessThan(app.buttons["Next page"].frame.midX, app.buttons["Previous page"].frame.midX)
        returnToFirstDemoPage()
        for _ in 0..<3 {
            if app.staticTexts["3 / 3"].exists { break }
            scroll.swipeRight(velocity: .slow)
        }
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5), "RTL continuous advances with a right swipe")
        waitForLoadedPage()
        capture("06-horizontal-continuous")
        app.buttons["Close book"].tap()
        openBook()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(scroll.exists)
        app.buttons["Reading options"].tap()
        XCTAssertEqual(app.buttons["reader-axis-horizontal"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["reader-direction-rtl"].value as? String, "Selected")
        app.buttons["Done"].tap()
        setReadingOptions()
    }

    func testSystemItalianAndManualEnglishSwitchPreservesDemo() {
        app.terminate()
        app.launchArguments = ["--demo", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT", "-app.language.v2", "system"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Libreria in sola lettura"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Segnali dal faro"].exists, "Books keep their content language")
        app.buttons["connection-settings"].tap()
        app.buttons["app-language"].tap()
        app.buttons["app-language-english"].tap()
        XCTAssertTrue(app.navigationBars["Connection"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Read-only library"].waitForExistence(timeout: 5))
        app.terminate()
        // Remove the launch-domain override to test the actual persisted choice.
        app.launchArguments = ["--demo", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Read-only library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["On-device demo"].exists, "Switching language preserves the connection")
        app.buttons["connection-settings"].tap()
        app.buttons["app-language"].tap()
        app.buttons["app-language-italian"].tap()
        XCTAssertTrue(app.navigationBars["Connessione"].waitForExistence(timeout: 5))
        app.buttons["Chiudi"].tap()
        XCTAssertTrue(app.staticTexts["Libreria in sola lettura"].waitForExistence(timeout: 5))
    }

    func testUnsupportedSystemLanguageFallsBackToEnglish() {
        app.terminate()
        app.launchArguments = ["--demo", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "-app.language.v2", "system"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Read-only library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Segnali dal faro"].exists)
    }
}
