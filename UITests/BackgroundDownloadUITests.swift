import XCTest
import Network
import UIKit

/// Real HTTP + real background URLSession; no URLProtocol, fake timers, or
/// production server. The server belongs to the test runner, not the reader.
private final class BackgroundReaderServer: @unchecked Sendable {
    let instance = "background-" + UUID().uuidString
    private let listener: NWListener
    private let queue = DispatchQueue(label: "background-reader-fixture")
    private let lock = NSLock()
    private var received: [(String, Date)] = []
    private var sent: [String] = []
    private var savedBookmark: [String: Any]?
    private var rejectWrites = false
    private var rejectConnections = false
    let pages = 8
    private(set) var port: UInt16 = 0
    private let png: Data
    var delay: Double = 5

    init() throws {
        png = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 360)).pngData { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 360))
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue); self.receive(connection, buffered: Data())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else { throw URLError(.cannotConnectToHost) }
        self.port = port.rawValue
    }
    var address: String { "http://127.0.0.1:\(port)" }
    var requests: [(String, Date)] { lock.lock(); defer { lock.unlock() }; return received }
    var delivered: [String] { lock.lock(); defer { lock.unlock() }; return sent }
    var bookmarkPage: Int? { lock.lock(); defer { lock.unlock() }; return savedBookmark?["page_index"] as? Int }
    var failBookmarkWrites: Bool {
        get { lock.lock(); defer { lock.unlock() }; return rejectWrites }
        set { lock.lock(); defer { lock.unlock() }; rejectWrites = newValue }
    }
    var failConnections: Bool {
        get { lock.lock(); defer { lock.unlock() }; return rejectConnections }
        set { lock.lock(); defer { lock.unlock() }; rejectConnections = newValue }
    }
    func stop() { listener.cancel() }
    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self, let data, error == nil else { connection.cancel(); return }
            var buffer = buffered; buffer.append(data)
            if let separator = buffer.range(of: Data("\r\n\r\n".utf8)),
               let text = String(data: buffer[..<separator.lowerBound], encoding: .utf8) {
                let lengthLine = text.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                let length = lengthLine.flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                guard length >= 0, length < 16384 else { connection.cancel(); return }
                if buffer.count - separator.upperBound < length {
                    if !complete { self.receive(connection, buffered: buffer) } else { connection.cancel() }
                    return
                }
                let parts = text.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard parts.count >= 2 else { connection.cancel(); return }
                let method = String(parts[0]), path = String(parts[1])
                self.lock.lock(); self.received.append((path, Date())); self.lock.unlock()
                if self.failConnections { connection.cancel(); return }
                let payload = buffer.subdata(in: separator.upperBound..<(separator.upperBound + length))
                let (status, body) = self.response(method, path: path, payload: payload)
                let isPage = path.contains("/pages/")
                self.queue.asyncAfter(deadline: .now() + (isPage ? self.delay : 0)) {
                    let header = "HTTP/1.1 \(status)\r\nContent-Type: \(isPage || path.hasSuffix("/cover") ? "image/png" : "application/json")\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { error in
                        if error == nil, isPage { self.lock.lock(); self.sent.append(path); self.lock.unlock() }
                        connection.cancel()
                    })
                }
            } else if !complete && buffer.count < 16384 { self.receive(connection, buffered: buffer) }
            else { connection.cancel() }
        }
    }
    private func response(_ method: String, path: String, payload: Data) -> (String, Data) {
        if path.contains("/pages/") || path.hasSuffix("/cover") { return ("200 OK", png) }
        if path == "/v1/series/background-series/bookmark" {
            lock.lock(); defer { lock.unlock() }
            if rejectWrites { return ("503 Service Unavailable", Data("{}".utf8)) }
            if method == "PUT", let input = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
               let book = input["book_id"] as? String, let page = input["page_index"] as? Int {
                savedBookmark = ["series_id": "background-series", "series_title": "Background download fixture",
                    "book_id": book, "label": "Fixture", "page_index": page, "updated_at": "2026-11-01T08:00:00Z"]
                return ("200 OK", try! JSONSerialization.data(withJSONObject: savedBookmark!))
            }
            if method == "DELETE" { savedBookmark = nil; return ("200 OK", Data("{}".utf8)) }
            return ("400 Bad Request", Data("{}".utf8))
        }
        let value: [String: Any]
        let series: [String: Any] = ["id": "background-series", "title": "Background download fixture",
            "description": "Original test images", "authors": [], "language": "it", "books_count": 2,
            "cover_path": "/v1/series/background-series/cover"]
        switch path {
        case "/v1/status": value = ["name": "Tankarr Reader", "api_version": 1, "read_only": true,
            "reading_state_writable": true, "instance_id": instance]
        case "/v1/bookmarks":
            lock.lock(); let items = savedBookmark.map { [$0] } ?? []; lock.unlock()
            value = ["items": items]
        case "/v1/library": value = ["items": [series]]
        case "/v1/series/background-series":
            value = ["books": (1...2).map { n in ["id": "bg-book-\(n)", "label": "Capitolo \(n)", "title": "Fixture \(n)",
                "volume": "", "chapter": String(n), "unit": "chapter", "language": "it"] }]
        case "/v1/books/bg-book-1", "/v1/books/bg-book-2":
            let first = path.hasSuffix("-1")
            value = ["id": path.components(separatedBy: "/").last!, "series_id": "background-series",
                "series_title": "Background download fixture", "title": first ? "Fixture 1" : "Fixture 2",
                "page_count": pages, "direction": "ltr", "mode": "paged",
                "previous_id": first ? NSNull() : "bg-book-1", "next_id": first ? "bg-book-2" : NSNull()]
        default: value = ["items": []]
        }
        return ("200 OK", try! JSONSerialization.data(withJSONObject: value))
    }
}

final class BackgroundDownloadUITests: XCTestCase {
    private var app: XCUIApplication!
    private var server: BackgroundReaderServer!
    override func setUpWithError() throws {
        continueAfterFailure = false
        server = try BackgroundReaderServer()
        app = XCUIApplication()
        app.launchArguments = ["--background-download-test", server.address, "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Background download fixture"].firstMatch.waitForExistence(timeout: 15))
    }
    override func tearDownWithError() throws { app?.terminate(); server?.stop() }
    private func queueBooks() {
        app.staticTexts["Background download fixture"].firstMatch.tap()
        app.buttons["series-downloads"].tap()
        app.buttons["download-series"].tap()
        waitUntil({ self.app.buttons["pause-download-bg-book-1"].exists ||
                    self.app.buttons["remove-download-bg-book-1"].exists }, seconds: 15)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["downloads"].tap()
    }
    private func waitUntil(_ condition: @escaping () -> Bool, seconds: TimeInterval = 100) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: seconds), .completed)
    }
    private func assertComplete() {
        XCTAssertTrue(app.buttons["remove-download-bg-book-1"].waitForExistence(timeout: 120))
        XCTAssertTrue(app.buttons["remove-download-bg-book-2"].waitForExistence(timeout: 120))
    }
    private func readyPage(_ counter: String) {
        XCTAssertTrue(app.staticTexts[counter].waitForExistence(timeout: 15))
        waitUntil({ self.app.buttons["Segnalibro"].isEnabled }, seconds: 15)
    }
    private func lastPage() {
        app.sliders["reader-page-slider"].adjust(toNormalizedSliderPosition: 1)
        for _ in 0..<2 {
            if app.staticTexts["8 / 8"].exists { break }
            waitUntil({ self.app.buttons["Segnalibro"].isEnabled }, seconds: 15)
            app.buttons["Pagina successiva"].tap()
        }
        readyPage("8 / 8")
    }

    func testChapterBoundariesAndSeriesBookmarkRespectOfflineAvailability() {
        server.delay = 0.1
        app.staticTexts["Background download fixture"].firstMatch.tap()
        app.staticTexts["Capitolo 1"].tap(); readyPage("1 / 8")
        lastPage()
        app.buttons["Pagina successiva"].tap(); readyPage("1 / 8")
        XCTAssertEqual(app.staticTexts["reader-book-title"].label, "Fixture 2")
        app.buttons["Segnalibro"].tap(); app.buttons["Salva segnalibro"].tap()
        XCTAssertTrue(app.staticTexts["Segnalibro a pagina 1"].waitForExistence(timeout: 10))
        app.buttons["Pagina precedente"].tap(); readyPage("8 / 8")
        XCTAssertEqual(app.staticTexts["reader-book-title"].label, "Fixture 1")
        app.buttons["Torna alla serie"].tap()
        XCTAssertTrue(app.buttons["series-resume-bookmark"].waitForExistence(timeout: 10))
        app.buttons["series-resume-bookmark"].tap(); readyPage("1 / 8")
        app.buttons["Pagina successiva"].tap(); readyPage("2 / 8")
        app.buttons["Chiudi libro"].tap()
        app.buttons["series-resume-bookmark"].tap(); readyPage("1 / 8")
        app.buttons["Chiudi libro"].tap()

        app.buttons["download-bg-book-1"].tap()
        XCTAssertTrue(app.buttons["remove-download-bg-book-1"].waitForExistence(timeout: 45))
        app.navigationBars.buttons.firstMatch.tap(); app.buttons["offline-mode"].tap()
        app.staticTexts["Background download fixture"].firstMatch.tap()
        let requests = server.requests.count
        app.buttons["series-resume-bookmark"].tap()
        XCTAssertTrue(app.alerts["Segnalibro non disponibile offline"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.staticTexts["Capitolo 1"].tap(); readyPage("8 / 8")
        app.buttons["Pagina successiva"].tap()
        XCTAssertTrue(app.alerts.staticTexts["Il capitolo successivo non è scaricato. Torna online per leggerlo."].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(app.staticTexts["reader-book-title"].label, "Fixture 1")
        XCTAssertEqual(server.requests.count, requests, "Offline boundary/resume must not fetch missing chapters")
    }

    func testDownloadedNeighboursAndAutomaticOfflineRecovery() {
        server.delay = 1
        queueBooks(); assertComplete(); app.buttons["Chiudi"].tap()
        server.failConnections = true
        // A real socket failure switches to cached library/chapters, without
        // changing the user's explicit offline preference.
        app.staticTexts["Background download fixture"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Capitolo 1"].waitForExistence(timeout: 30))
        app.staticTexts["Capitolo 1"].tap(); readyPage("1 / 8"); lastPage()
        app.images["reader-page"].firstMatch.swipeLeft(); readyPage("1 / 8")
        XCTAssertEqual(app.staticTexts["reader-book-title"].label, "Fixture 2")
        app.images["reader-page"].firstMatch.swipeRight(); readyPage("8 / 8")
        XCTAssertEqual(app.staticTexts["reader-book-title"].label, "Fixture 1")
        app.buttons["Chiudi libro"].tap(); app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Offline automatico"].waitForExistence(timeout: 10))
        server.failConnections = false
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Libreria in sola lettura"].waitForExistence(timeout: 20))
        // Manual Offline remains selected even with working network and a new foreground.
        app.buttons["offline-mode"].tap()
        XCTAssertTrue(app.staticTexts["Lettura offline"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Lettura offline"].waitForExistence(timeout: 10))
        app.buttons["return-online"].tap()
        XCTAssertTrue(app.staticTexts["Libreria in sola lettura"].waitForExistence(timeout: 20))
    }

    func testDownloadsContinueWhileReaderIsInBackground() {
        queueBooks()
        XCUIDevice.shared.press(.home)
        waitUntil({ self.app.state != .runningForeground }, seconds: 15)
        let backgrounded = Date()
        waitUntil({ Set(self.server.delivered).count == self.server.pages * 2 })
        XCTAssertNotEqual(app.state, .runningForeground)
        XCTAssertTrue(server.requests.contains { $0.0.contains("/pages/") && $0.1.timeIntervalSince(backgrounded) > 15 },
            "Network transfers must continue beyond the app's short foreground grace period")
        app.activate()
        assertComplete()
        app.buttons["use-offline"].tap()
        app.buttons["offline-book-bg-book-2"].tap()
        XCTAssertTrue(app.images["reader-page"].firstMatch.waitForExistence(timeout: 10))
    }

    func testClosingAndReopeningResumesWholeQueueWithoutReselectingChapters() {
        queueBooks()
        let progress = app.progressIndicators["download-progress-bg-book-1"]
        waitUntil({ (Int(progress.value as? String ?? "0") ?? 0) >= 2 }, seconds: 45)
        let firstPage = "/v1/books/bg-book-1/pages/0"
        let firstPageRequests = server.requests.filter { $0.0 == firstPage }.count
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["downloads"].waitForExistence(timeout: 20))
        app.buttons["downloads"].tap()
        assertComplete()
        XCTAssertEqual(server.requests.filter { $0.0 == firstPage }.count, firstPageRequests,
            "A page committed before process termination must not be downloaded again")
    }

    func testRemovingActiveQueueDoesNotReturnAfterRelaunch() {
        queueBooks()
        app.buttons["remove-all-downloads"].tap()
        app.buttons["confirm-remove-all-downloads"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Nessun download"].waitForExistence(timeout: 15))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["downloads"].waitForExistence(timeout: 20))
        app.buttons["downloads"].tap()
        XCTAssertTrue(app.staticTexts["Nessun download"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["offline-book-bg-book-1"].exists)
        XCTAssertFalse(app.buttons["offline-book-bg-book-2"].exists)
        XCTAssertFalse(app.buttons["remove-all-downloads"].exists)
    }

    func testSeriesSharesLiveProgressPauseResumeAndRemovalWithDownloads() {
        app.staticTexts["Background download fixture"].firstMatch.tap()
        app.buttons["series-downloads"].tap()
        app.buttons["download-series"].tap()
        let progress = app.progressIndicators["download-progress-bg-book-1"]
        waitUntil({ (Int(progress.value as? String ?? "0") ?? 0) >= 1 }, seconds: 45)
        XCTAssertTrue(app.staticTexts["download-pages-bg-book-1"].exists)
        XCTAssertTrue(app.staticTexts["series-download-summary"].label.contains("2 in coda"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "series-live-download-progress"; screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["pause-download-bg-book-1"].tap()
        XCTAssertTrue(app.buttons["download-bg-book-1"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["download-bg-book-1"].label, "Riprendi download")
        XCTAssertTrue(app.staticTexts["download-state-bg-book-1"].label.contains("In pausa"))
        let savedPages = progress.value as? String
        XCTAssertNotNil(savedPages)

        // Both screens must use the same saved count and state, not independent
        // timers that appear to restart a download when navigating between them.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["downloads"].tap()
        XCTAssertEqual(app.progressIndicators["download-progress-bg-book-1"].value as? String, savedPages)
        XCTAssertTrue(app.buttons["download-bg-book-1"].exists)
        app.buttons["Chiudi"].tap()
        app.staticTexts["Background download fixture"].firstMatch.tap()
        XCTAssertEqual(progress.value as? String, savedPages)
        app.buttons["download-bg-book-1"].tap()
        XCTAssertTrue(app.buttons["pause-download-bg-book-1"].waitForExistence(timeout: 10))
        assertComplete()
        XCTAssertTrue(app.staticTexts["series-download-summary"].label.contains("2 libri scaricati"))
        XCTAssertFalse(progress.exists)

        app.buttons["remove-download-bg-book-1"].tap()
        app.buttons["Rimuovi download"].firstMatch.tap()
        XCTAssertTrue(app.buttons["download-bg-book-1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["remove-download-bg-book-1"].exists)
        XCTAssertTrue(app.buttons["remove-download-bg-book-2"].exists)
        XCTAssertFalse(app.staticTexts["download-pages-bg-book-1"].exists)
    }

    func testOfflineBookmarkSurvivesRelaunchRetriesFailureAndSyncsRemoval() {
        server.delay = 1
        queueBooks(); assertComplete()
        app.buttons["use-offline"].tap()
        app.buttons["offline-book-bg-book-1"].tap()
        XCTAssertTrue(app.images["reader-page"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Pagina successiva"].tap()
        waitUntil({ self.app.buttons["Segnalibro"].isEnabled }, seconds: 10)
        app.buttons["Segnalibro"].tap(); app.buttons["Salva segnalibro"].tap()
        XCTAssertTrue(app.staticTexts["Segnalibro a pagina 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["bookmark-sync-pending"].exists || app.staticTexts["bookmark-sync-pending"].exists)
        XCTAssertNil(server.bookmarkPage, "Offline editing must not contact the server")

        // Use normal production restore, not the fixture's connect-on-launch shortcut.
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Lettura offline"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Segnalibri"].tap()
        XCTAssertTrue(app.buttons["bookmark-background-series"].waitForExistence(timeout: 10))
        app.buttons["bookmark-background-series"].tap()
        XCTAssertTrue(app.staticTexts["Segnalibro a pagina 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["bookmark-sync-pending"].exists || app.staticTexts["bookmark-sync-pending"].exists)
        app.buttons["Chiudi libro"].tap(); app.buttons["Chiudi"].tap()

        server.failBookmarkWrites = true
        app.buttons["offline-mode"].tap()
        waitUntil({ self.app.buttons["offline-mode"].value as? String == "Disattiva" }, seconds: 15)
        app.buttons["Segnalibri"].tap()
        XCTAssertTrue(app.buttons["Aggiorna segnalibri"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["bookmark-background-series"].exists)
        XCTAssertNil(server.bookmarkPage, "A failed request must keep the local edit for retry")
        server.failBookmarkWrites = false
        // Reopening online must retry without asking the reader to save again.
        app.terminate(); app.launch()
        waitUntil({ self.server.bookmarkPage == 1 }, seconds: 15)
        XCTAssertTrue(app.buttons["Segnalibri"].waitForExistence(timeout: 15))
        app.buttons["Segnalibri"].tap()
        waitUntil({ !self.app.otherElements["bookmark-sync-pending"].exists && !self.app.staticTexts["bookmark-sync-pending"].exists }, seconds: 10)
        app.buttons["Chiudi"].tap()

        app.buttons["offline-mode"].tap()
        waitUntil({ self.app.buttons["offline-mode"].value as? String == "Attiva" }, seconds: 10)
        app.buttons["Segnalibri"].tap(); app.buttons["bookmark-background-series"].tap()
        waitUntil({ self.app.buttons["Segnalibro"].isEnabled }, seconds: 10)
        app.buttons["Segnalibro"].tap(); app.buttons["Rimuovi segnalibro"].tap()
        waitUntil({ !self.app.staticTexts["Segnalibro a pagina 2"].exists }, seconds: 10)
        XCTAssertEqual(server.bookmarkPage, 1)
        app.buttons["Chiudi libro"].tap(); app.buttons["Chiudi"].tap()
        app.buttons["offline-mode"].tap()
        waitUntil({ self.server.bookmarkPage == nil }, seconds: 15)
        app.buttons["Segnalibri"].tap()
        XCTAssertTrue(app.staticTexts["Nessun segnalibro"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["bookmark-background-series"].exists)
    }
}
