import Foundation
import Network
import XCTest
@testable import TankarrReaderCore

/// Loopback-only HTTP fixture exercises the real URLSession download path.
/// No user profile, server, credentials, or library is used by these tests.
private final class PageServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "offline-download-network-test")
    private let lock = NSLock()
    private var paths: [String] = []
    private let response: (String) -> String
    private(set) var port: UInt16 = 0
    init(response: @escaping (String) -> String) throws {
        self.response = response
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
            connection.start(queue: self.queue)
            self.receive(connection, buffered: Data())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let value = listener.port, value.rawValue > 0 else {
            listener.cancel(); throw URLError(.cannotConnectToHost)
        }
        port = value.rawValue
    }
    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self, let data, error == nil else { connection.cancel(); return }
            var buffer = buffered; buffer.append(data)
            if let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") {
                let path = text.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                self.lock.lock(); self.paths.append(path); self.lock.unlock()
                connection.send(content: Data(self.response(path).utf8), completion: .contentProcessed { _ in connection.cancel() })
            } else if !complete && buffer.count < 16384 { self.receive(connection, buffered: buffer) }
            else { connection.cancel() }
        }
    }
    var requests: [String] { lock.lock(); defer { lock.unlock() }; return paths }
    func stop() { listener.cancel() }
    deinit { listener.cancel() }
}

final class OfflineNetworkTests: XCTestCase {
    func testCoverRetriesTemporaryFailureAndRecovers() async throws {
        var attempts = 0
        let server = try PageServer { _ in
            attempts += 1
            if attempts == 1 {
                return "HTTP/1.1 503 Busy\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            }
            return "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: 5\r\nConnection: close\r\n\r\ncover"
        }
        defer { server.stop() }
        let api = ReaderAPI(base: URL(string: "http://127.0.0.1:\(server.port)")!, username: "fixture", password: "fixture-only")
        let data = try await api.cover("series")
        XCTAssertEqual(data, Data("cover".utf8))
        XCTAssertEqual(server.requests, ["/v1/series/series/cover", "/v1/series/series/cover"])
    }

    func testCoverDoesNotRetryMissingOrUnauthorizedOrRedirect() async throws {
        for status in [302, 401, 404] {
            let server = try PageServer { _ in
                "HTTP/1.1 \(status) Test\r\nLocation: https://example.invalid/private\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            }
            defer { server.stop() }
            let api = ReaderAPI(base: URL(string: "http://127.0.0.1:\(server.port)")!, username: "fixture", password: "fixture-only")
            do { _ = try await api.cover("series"); XCTFail("Must reject") }
            catch { XCTAssertEqual(error as? ReaderError, status == 401 ? .unauthorized : .unavailable(status)) }
            XCTAssertEqual(server.requests.count, 1)
        }
    }

    func testHTTPPagesBecomeOfflineBookAndSurviveServerShutdown() async throws {
        let server = try PageServer { path in
            let body = "downloaded-" + path
            return "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        }
        defer { server.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let api = ReaderAPI(base: URL(string: "http://127.0.0.1:\(server.port)")!, username: "fixture", password: "fixture-only")
        let account = OfflineAccount(instance: "loopback-fixture", username: "fixture")
        let series = DemoCatalog.series[0], listing = try DemoCatalog.books(for: DemoCatalog.series[0].id)[0]
        let book = try DemoCatalog.book(listing.id)
        let store = OfflineStore(root: root, freeBytes: { _ in 10_000_000_000 })
        let result = try await OfflineTransfer.run(store: store, account: account, book: book, series: series, listing: listing,
            fetchPage: { try await api.downloadPage(book: book.id, index: $0) }, progress: { _ in })
        XCTAssertTrue(result.complete)
        XCTAssertEqual(server.requests, (0..<3).map { "/v1/books/\(book.id)/pages/\($0)" })
        server.stop()
        let reopened = OfflineStore(root: root, freeBytes: { _ in 10_000_000_000 })
        for index in 0..<3 {
            let data = try await reopened.page(book.id, index: index, account: account)
            XCTAssertEqual(data, Data("downloaded-/v1/books/\(book.id)/pages/\(index)".utf8))
        }
    }

    func testDownloadRefusesRedirectsAndAuthenticationFailures() async throws {
        for status in [302, 401, 503] {
            let server = try PageServer { _ in
                "HTTP/1.1 \(status) Test\r\nLocation: https://example.invalid/must-not-receive-credentials\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            }
            defer { server.stop() }
            let api = ReaderAPI(base: URL(string: "http://127.0.0.1:\(server.port)")!, username: "fixture", password: "fixture-only")
            do { _ = try await api.downloadPage(book: "book", index: 0); XCTFail("Must reject HTTP \(status)") }
            catch { XCTAssertEqual(error as? ReaderError, status == 401 ? .unauthorized : .unavailable(status)) }
            XCTAssertEqual(server.requests.count, 1)
        }
    }
}
