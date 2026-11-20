import XCTest
@testable import TankarrReaderCore

final class DemoAndProgressTests: XCTestCase {
    func testEveryDemoBookHasReadablePagesAndValidIdentifiers() throws {
        var modes = Set<String>(), directions = Set<String>()
        XCTAssertEqual(DemoCatalog.series.count, 3)
        for series in DemoCatalog.series {
            XCTAssertNoThrow(try Endpoint.identifier(series.id))
            let books = try DemoCatalog.books(for: series.id)
            XCTAssertEqual(books.count, series.booksCount)
            for item in books {
                XCTAssertNoThrow(try Endpoint.identifier(item.id))
                let book = try DemoCatalog.book(item.id)
                modes.insert(book.mode); directions.insert(book.direction)
                XCTAssertGreaterThan(book.pageCount, 1)
                for index in 0..<book.pageCount {
                    let page = try DemoCatalog.page(book.id, at: index)
                    XCTAssertEqual(page.seriesID, series.id)
                    XCTAssertEqual(page.index, index)
                    XCTAssertEqual(page.count, book.pageCount)
                    XCTAssertFalse(page.narration.isEmpty)
                }
                XCTAssertThrowsError(try DemoCatalog.page(book.id, at: -1))
                XCTAssertThrowsError(try DemoCatalog.page(book.id, at: book.pageCount))
            }
        }
        XCTAssertEqual(modes, ["manga", "webtoon"])
        XCTAssertEqual(directions, ["ltr", "rtl"])
    }

    func testDemoRejectsNonDemoResources() {
        XCTAssertThrowsError(try DemoCatalog.books(for: "private-server-series"))
        XCTAssertThrowsError(try DemoCatalog.book("private-server-book"))
        XCTAssertThrowsError(try DemoCatalog.page("../private", at: 0))
    }

    func testProgressSeparatesServersAndDemoAndClearsOnlyPositions() throws {
        let suite = "app.tankarr.reader.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let progress = ReadingProgress(defaults: defaults)
        defaults.set(Data("profile fixture".utf8), forKey: "serverProfile")
        defaults.set(true, forKey: "demoMode")
        progress.save(6, book: "book", instance: "server-a")
        progress.save(2, book: "book", instance: "server-b")
        progress.save(1, book: "book", instance: DemoCatalog.instanceID)
        XCTAssertEqual(progress.position(book: "book", instance: "server-a"), 6)
        XCTAssertEqual(progress.position(book: "book", instance: "server-b"), 2)
        XCTAssertEqual(progress.position(book: "book", instance: DemoCatalog.instanceID), 1)
        progress.clear()
        XCTAssertEqual(progress.position(book: "book", instance: "server-a"), 0)
        XCTAssertEqual(progress.position(book: "book", instance: DemoCatalog.instanceID), 0)
        XCTAssertNotNil(defaults.data(forKey: "serverProfile"))
        XCTAssertTrue(defaults.bool(forKey: "demoMode"))
    }

    func testInvalidStoredOrNewPositionNeverBecomesNegative() throws {
        let suite = "app.tankarr.reader.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let progress = ReadingProgress(defaults: defaults)
        defaults.set(-5, forKey: "page.server.book")
        XCTAssertEqual(progress.position(book: "book", instance: "server"), 0)
        progress.save(-9, book: "book", instance: "server")
        XCTAssertEqual(defaults.integer(forKey: "page.server.book"), 0)
    }

    func testResumeUsesExplicitBookmarkThenLocalThenServerAndClamps() throws {
        let suite = "app.tankarr.reader.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let progress = ReadingProgress(defaults: defaults)
        let book = ReaderBook(id: "book", seriesTitle: "Series", title: "Volume", pageCount: 8, direction: "ltr",
            mode: "manga", previousId: nil, nextId: nil, seriesId: "series", pageIndex: 4, bookmarked: true, bookmarkPageIndex: 4)
        XCTAssertNil(progress.storedPosition(book: "book", instance: "server"))
        XCTAssertEqual(progress.resumePosition(book: book, instance: "server"), 4)
        progress.save(0, book: "book", instance: "server")
        XCTAssertEqual(progress.resumePosition(book: book, instance: "server"), 0, "Page zero is an actual local position")
        progress.save(6, book: "book", instance: "server")
        XCTAssertEqual(progress.resumePosition(book: book, instance: "server"), 6)
        XCTAssertEqual(progress.resumePosition(book: book, instance: "server", openingPage: 4), 4, "Opening a bookmark overrides local resume")
        XCTAssertEqual(progress.resumePosition(book: book, instance: "server", openingPage: 99), 7)
        XCTAssertEqual(progress.resumePosition(book: book, instance: "server", openingPage: -2), 0)
        let unbookmarked = ReaderBook(id: "other", seriesTitle: "Series", title: "Other", pageCount: 8, direction: "ltr",
            mode: "manga", previousId: nil, nextId: nil, pageIndex: 5, bookmarked: false)
        XCTAssertEqual(progress.resumePosition(book: unbookmarked, instance: "server"), 0)
    }

    func testDemoBookmarkReplacesOnlySameSeriesAndDoesNotFollowLocalProgress() throws {
        let suite = "app.tankarr.reader.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DemoBookmarkStore(defaults: defaults)
        let progress = ReadingProgress(defaults: defaults)
        let first = ReaderBookmark(seriesId: "series", seriesTitle: "S", bookId: "book", label: "V1", pageIndex: 1, updatedAt: "2026-10-29T12:00:00Z")
        let other = ReaderBookmark(seriesId: "other", seriesTitle: "O", bookId: "other-book", label: "V1", pageIndex: 3, updatedAt: "2026-10-29T12:00:01Z")
        store.save(first); store.save(other)
        progress.save(6, book: "book", instance: DemoCatalog.instanceID)
        XCTAssertEqual(store.all().first(where: { $0.seriesId == "series" })?.pageIndex, 1)
        let moved = ReaderBookmark(seriesId: "series", seriesTitle: "S", bookId: "book-2", label: "V2", pageIndex: 0, updatedAt: "2026-10-29T12:00:02Z")
        store.save(moved)
        XCTAssertEqual(store.all().count, 2)
        XCTAssertEqual(store.all().first?.bookId, "book-2")
        XCTAssertEqual(DemoBookmarkStore(defaults: defaults).all(), store.all(), "Bookmarks survive reopening the store")
        store.remove(series: "series")
        XCTAssertEqual(store.all(), [other])
        progress.save(7, book: "book-2", instance: DemoCatalog.instanceID)
        XCTAssertEqual(store.all(), [other], "Turning pages cannot recreate a removed bookmark")
        store.clear()
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertEqual(progress.position(book: "book", instance: DemoCatalog.instanceID), 6)
    }

    func testStatusFilterMatchesGatewayStatusesAndTreatsMissingAsUnknown() throws {
        let json = Data(#"[{"id":"a","title":"A","description":"","authors":[],"language":"en","books_count":1,"cover_path":"","status":"completed"},{"id":"b","title":"B","description":"","authors":[],"language":"en","books_count":1,"cover_path":"","status":"hiatus"},{"id":"c","title":"C","description":"","authors":[],"language":"en","books_count":1,"cover_path":""},{"id":"d","title":"D","description":"","authors":[],"language":"en","books_count":1,"cover_path":"","status":"weird"}]"#.utf8)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode([LibrarySeries].self, from: json)
        XCTAssertEqual(rows.map(\.publicationStatus), [.completed, .hiatus, .unknown, .unknown])
        XCTAssertEqual(rows.filter { SeriesStatusFilter.completed.matches($0) }.map(\.id), ["a"])
        XCTAssertEqual(rows.filter { SeriesStatusFilter.unknown.matches($0) }.map(\.id), ["c", "d"])
        XCTAssertEqual(rows.filter { SeriesStatusFilter.all.matches($0) }.count, 4)
        XCTAssertEqual(Set(DemoCatalog.series.map(\.publicationStatus)), [.completed, .ongoing, .hiatus])
    }

    func testStatusMenuListsOnlyStatesThatHaveSeries() {
        func row(_ id: String, _ status: String?) -> LibrarySeries {
            LibrarySeries(id: id, title: id, description: "", authors: [], language: "en", booksCount: 1, coverPath: "", status: status)
        }
        let mixed = [row("a", "completed"), row("b", "completed"), row("c", "ongoing")]
        XCTAssertEqual(SeriesStatusFilter.available(in: mixed), [.all, .ongoing, .completed])
        XCTAssertFalse(SeriesStatusFilter.available(in: mixed).contains(.unknown), "No series without status: no Unknown entry")
        XCTAssertTrue(SeriesStatusFilter.isUseful(for: mixed))
        let withUnknown = mixed + [row("d", nil)]
        XCTAssertEqual(SeriesStatusFilter.available(in: withUnknown), [.all, .ongoing, .completed, .unknown])
        let single = [row("a", "completed"), row("b", "completed")]
        XCTAssertEqual(SeriesStatusFilter.available(in: single), [.all, .completed])
        XCTAssertFalse(SeriesStatusFilter.isUseful(for: single), "One state only: hide the filter")
        XCTAssertTrue(SeriesStatusFilter.isUseful(for: single, selected: .hiatus), "A saved choice must stay reachable")
        XCTAssertEqual(SeriesStatusFilter.available(in: single, selected: .hiatus), [.all, .completed, .hiatus])
        XCTAssertFalse(SeriesStatusFilter.isUseful(for: []))
    }
}
