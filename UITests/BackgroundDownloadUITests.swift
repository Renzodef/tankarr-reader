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
    func stop() { listener.cancel() }
    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self, let data, error == nil else { connection.cancel(); return }
            var buffer = buffered; buffer.append(data)
            if let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") {
                let path = text.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                self.lock.lock(); self.received.append((path, Date())); self.lock.unlock()
                let body = self.body(path)
                let isPage = path.contains("/pages/")
                self.queue.asyncAfter(deadline: .now() + (isPage ? self.delay : 0)) {
                    let header = "HTTP/1.1 200 OK\r\nContent-Type: \(isPage || path.hasSuffix("/cover") ? "image/png" : "application/json")\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { error in
                        if error == nil, isPage { self.lock.lock(); self.sent.append(path); self.lock.unlock() }
                        connection.cancel()
                    })
                }
            } else if !complete && buffer.count < 16384 { self.receive(connection, buffered: buffer) }
            else { connection.cancel() }
        }
    }
    private func body(_ path: String) -> Data {
        if path.contains("/pages/") || path.hasSuffix("/cover") { return png }
        let value: [String: Any]
        let series: [String: Any] = ["id": "background-series", "title": "Background download fixture",
            "description": "Original test images", "authors": [], "language": "it", "books_count": 2,
            "cover_path": "/v1/series/background-series/cover"]
        switch path {
        case "/v1/status": value = ["name": "Tankarr Reader", "api_version": 1, "read_only": true, "instance_id": instance]
        case "/v1/library": value = ["items": [series]]
        case "/v1/series/background-series":
            value = ["books": (1...2).map { n in ["id": "bg-book-\(n)", "label": "Capitolo \(n)", "title": "Fixture \(n)",
                "volume": "", "chapter": String(n), "unit": "chapter", "language": "it"] }]
        case "/v1/books/bg-book-1", "/v1/books/bg-book-2":
            value = ["id": path.components(separatedBy: "/").last!, "series_id": "background-series",
                "series_title": "Background download fixture", "title": "Fixture", "page_count": pages, "direction": "ltr", "mode": "paged"]
        default: value = ["items": []]
        }
        return try! JSONSerialization.data(withJSONObject: value)
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
        XCTAssertTrue(app.buttons["pause-download-bg-book-1"].waitForExistence(timeout: 15))
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
}
