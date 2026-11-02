import XCTest
@testable import TankarrReaderCore

final class ReaderCoreTests: XCTestCase {
    func testRejectsUnsafeAddresses() {
        for value in ["http://example.org", "https://user:secret@example.org", "https://example.org/?token=x", "https://example.org/#x", "file:///tmp", "https://example.org/../admin", "http://127.1", "http://0x7f000001", "http://192.168.1.01", "https://example.org:0"] {
            XCTAssertThrowsError(try Endpoint.validate(value), value)
        }
    }
    func testHTTPSAndExplicitLocalHTTP() throws {
        for value in ["https://reader.example.org", "https://nas.local:9443", "http://192.168.1.2:8789", "http://10.1.2.3", "http://172.16.1.2", "http://localhost:8000"] {
            XCTAssertNoThrow(try Endpoint.validate(value))
        }
        XCTAssertEqual(try Endpoint.validate("https://reader.example.org/").absoluteString, "https://reader.example.org")
    }
    func testAutomaticOrderAndDeduplication() throws {
        var profile = ServerProfile(localAddress: "https://nas.local", remoteAddress: "https://reader.example.org", username: "reader")
        XCTAssertEqual(try profile.candidates().map(\.host), ["nas.local", "reader.example.org"])
        profile.remoteAddress = profile.localAddress + "/"
        XCTAssertEqual(try profile.candidates().count, 1)
        profile.mode = .remote
        XCTAssertEqual(try profile.candidates().count, 1)
    }
    func testRequestNeverAllowsManagementOrUnsafeIdentifier() throws {
        let base = try Endpoint.validate("https://reader.example.org")
        for path in ["/api/settings", "/api/auth/api-key", "//other.example/v1/library", "/v1/library?fresh=true", "/v1/books/a/../settings"] {
            XCTAssertThrowsError(try Endpoint.request(base: base, path: path, username: "reader", password: "fixture-password"))
        }
        for id in ["..", "a/b", "%2e", "a?x", "a#x", "valid\n"] { XCTAssertThrowsError(try Endpoint.identifier(id)) }
        let request = try Endpoint.request(base: base, path: "/v1/books/book-123/pages/0", username: "reader", password: "fixture-password")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.url?.host, "reader.example.org")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Key"))
    }
    func testProfileDoesNotSerializePassword() throws {
        let data = try JSONEncoder().encode(ServerProfile(remoteAddress: "https://reader.example.org", username: "reader"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("password"))
    }
    func testProviderIdentifiersWithDotsRemainSingleSafePathComponents() throws {
        let base = try Endpoint.validate("https://reader.example.org")
        XCTAssertEqual(try Endpoint.identifier("provider.series"), "provider.series")
        let request = try Endpoint.request(base: base, path: "/v1/books/provider.chapter-373/pages/0",
            username: "reader", password: "fixture-password")
        XCTAssertEqual(request.url?.path, "/v1/books/provider.chapter-373/pages/0")
        for path in ["/v1/books/../pages/0", "/v1/series/../bookmark", "/v1/books/.hidden/pages/0"] {
            XCTAssertThrowsError(try Endpoint.request(base: base, path: path, username: "reader", password: "fixture-password"))
        }
    }
    func testOnlyBookmarkMutationsArePermittedAndCarryCSRFHeader() throws {
        let base = try Endpoint.validate("https://reader.example.org")
        let body = Data(#"{"book_id":"book-1","page_index":2}"#.utf8)
        for method in ["PUT", "DELETE"] {
            let requestBody = method == "PUT" ? body : nil
            let request = try Endpoint.request(base: base, path: "/v1/series/series-1/bookmark", username: "reader",
                password: "fixture-password", method: method, jsonBody: requestBody)
            XCTAssertEqual(request.httpMethod, method)
            XCTAssertEqual(request.httpBody, requestBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), method == "PUT" ? "application/json" : nil)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Tankarr-Reader"), "1")
            for path in ["/v1/library", "/v1/books/book-1", "/v1/books/book-1/pages/0", "/v1/bookmarks", "/v1/series/series-1", "/api/settings"] {
                XCTAssertThrowsError(try Endpoint.request(base: base, path: path, username: "reader",
                    password: "fixture-password", method: method, jsonBody: requestBody))
            }
        }
        for method in ["GET", "POST", "PATCH"] {
            XCTAssertThrowsError(try Endpoint.request(base: base, path: "/v1/series/series-1/bookmark", username: "reader",
                password: "fixture-password", method: method, jsonBody: body))
        }
        XCTAssertThrowsError(try Endpoint.request(base: base, path: "/v1/series/series-1/bookmark", username: "reader",
            password: "fixture-password", method: "PUT"))
        XCTAssertThrowsError(try Endpoint.request(base: base, path: "/v1/series/series-1/bookmark", username: "reader",
            password: "fixture-password", method: "DELETE", jsonBody: Data("{}".utf8)))
        let listing = try Endpoint.request(base: base, path: "/v1/bookmarks", username: "reader", password: "fixture-password")
        XCTAssertEqual(listing.httpMethod, "GET")
        XCTAssertNil(listing.httpBody)
    }
    func testBookmarkProtocolAndOlderServerMetadataDecode() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = #"{"items":[{"series_id":"series-1","series_title":"Series","book_id":"book-1","label":"Volume 1","page_index":5,"updated_at":"2026-10-29T12:00:00Z"}]}"#
        let result = try decoder.decode(BookmarksResponse.self, from: Data(raw.utf8))
        XCTAssertEqual(result.items.first?.seriesId, "series-1")
        XCTAssertEqual(result.items.first?.pageIndex, 5)
        let oldStatus = #"{"name":"Tankarr Reader","api_version":1,"read_only":true,"instance_id":"fixture"}"#
        XCTAssertNil(try decoder.decode(ReaderStatus.self, from: Data(oldStatus.utf8)).readingStateWritable)
        let status = #"{"name":"Tankarr Reader","api_version":1,"read_only":true,"instance_id":"fixture","reading_state_writable":true}"#
        XCTAssertEqual(try decoder.decode(ReaderStatus.self, from: Data(status.utf8)).readingStateWritable, true)
        let book = #"{"id":"book-1","series_id":"series-1","series_title":"S","title":"T","page_count":9,"direction":"rtl","mode":"manga","previous_id":null,"next_id":null,"page_index":5,"bookmarked":true,"bookmark_page_index":5}"#
        let metadata = try decoder.decode(ReaderBook.self, from: Data(book.utf8))
        XCTAssertEqual(metadata.seriesId, "series-1")
        XCTAssertEqual(metadata.bookmarkPageIndex, 5)
        XCTAssertEqual(metadata.bookmarked, true)
    }
    func testSnakeCaseLibraryAndReaderMetadata() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let raw = #"{"items":[{"id":"a","title":"A","description":"D","authors":[],"language":"en","books_count":2,"cover_path":"/v1/series/a/cover"}]}"#
        let result = try decoder.decode(LibraryResponse.self, from: Data(raw.utf8))
        XCTAssertEqual(result.items[0].booksCount, 2)
        let book = #"{"id":"b","series_title":"S","title":"T","page_count":4,"direction":"rtl","mode":"manga","previous_id":null,"next_id":"c"}"#
        XCTAssertEqual(try decoder.decode(ReaderBook.self, from: Data(book.utf8)).nextId, "c")
    }
    func testRedirectDelegateAlwaysRefuses() {
        let delegate = RefuseRedirects()
        let request = URLRequest(url: URL(string: "https://other.example")!)
        let task = URLSession.shared.dataTask(with: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        delegate.urlSession(.shared, task: task, willPerformHTTPRedirection: response, newRequest: request) { XCTAssertNil($0) }
        task.cancel()
    }
}
