import Foundation
import XCTest
@testable import TankarrReaderCore

final class OfflineDownloadsTests: XCTestCase {
    private var root: URL!
    private let account = OfflineAccount(instance: "server-one", username: "reader")
    private var series: LibrarySeries { DemoCatalog.series[0] }
    private var listing: LibraryBook { try! DemoCatalog.books(for: series.id)[0] }
    private var book: ReaderBook { try! DemoCatalog.book(listing.id) }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OfflineTests-\(UUID())")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func store(free: Int64 = 10_000_000_000) -> OfflineStore { OfflineStore(root: root, freeBytes: { _ in free }) }
    private func download(_ store: OfflineStore) async throws -> OfflineDownload {
        try await OfflineTransfer.run(store: store, account: account, book: book, series: series, listing: listing,
            fetchPage: { Data("page-\($0)".utf8) }, progress: { _ in })
    }

    func testCompleteDownloadSurvivesRelaunchAndReadsEveryPageWithoutNetwork() async throws {
        let done = try await download(store())
        XCTAssertTrue(done.complete)
        XCTAssertEqual(done.downloadedPages, 3)
        XCTAssertEqual(done.bytes, 18)
        let reopened = store()
        let saved = try await reopened.book(book.id, account: account)
        XCTAssertEqual(saved?.title, book.title)
        XCTAssertEqual(saved?.direction, book.direction)
        for i in 0..<3 {
            let page = try await reopened.page(book.id, index: i, account: account)
            XCTAssertEqual(page, Data("page-\(i)".utf8))
        }
        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
        let manifest = try String(contentsOf: root.appendingPathComponent(account.key).appendingPathComponent(book.id).appendingPathComponent("download.json"))
        XCTAssertFalse(manifest.contains("password"))
        XCTAssertFalse(manifest.contains("https://"))
        let mode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(account.key).appendingPathComponent(book.id).appendingPathComponent("download.json").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testInterruptedDownloadIsNotReadableAndResumeFetchesOnlyMissingPages() async throws {
        let first = store()
        do {
            _ = try await OfflineTransfer.run(store: first, account: account, book: book, series: series, listing: listing,
                fetchPage: { index in
                    if index == 1 { throw URLError(.networkConnectionLost) }
                    return Data("page-\(index)".utf8)
                }, progress: { _ in })
            XCTFail("Network failure must propagate")
        } catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        let partial = try await first.record(book.id, account: account)
        let readable = try await first.book(book.id, account: account)
        XCTAssertEqual(partial?.downloadedPages, 1)
        XCTAssertEqual(partial?.complete, false)
        XCTAssertNil(readable)
        var requested: [Int] = []
        let done = try await OfflineTransfer.run(store: store(), account: account, book: book, series: series, listing: listing,
            fetchPage: { requested.append($0); return Data("page-\($0)".utf8) }, progress: { _ in })
        XCTAssertEqual(requested, [1, 2])
        XCTAssertTrue(done.complete)
    }

    func testCancellationCannotPublishAnIncompleteBook() async throws {
        let disk = store(), account = account, book = book, series = series, listing = listing
        let task = Task {
            try await OfflineTransfer.run(store: disk, account: account, book: book, series: series, listing: listing,
                fetchPage: { Data("page-\($0)".utf8) }, progress: { record in
                    if record.downloadedPages == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                })
        }
        do { _ = try await task.value; XCTFail("Must cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
        let partial = try await disk.record(book.id, account: account)
        XCTAssertEqual(partial?.downloadedPages, 1)
        XCTAssertEqual(partial?.complete, false)
    }

    func testAccountsAndServersCannotReadOrDeleteEachOthersCopies() async throws {
        let disk = store()
        _ = try await download(disk)
        for other in [OfflineAccount(instance: "server-one", username: "other"),
                      OfflineAccount(instance: "server-two", username: "reader")] {
            let records = try await disk.downloads(account: other)
            let readable = try await disk.book(book.id, account: other)
            XCTAssertTrue(records.isEmpty); XCTAssertNil(readable)
            try await disk.remove(book.id, account: other)
            try await disk.removeAll(account: other)
        }
        XCTAssertEqual(account, OfflineAccount(instance: "server-one", username: "reader"))
        let kept = try await disk.book(book.id, account: account)
        XCTAssertNotNil(kept)
    }

    func testRemovalFencesAnInFlightResponseAndDoesNotRecreateTheBook() async throws {
        let disk = store()
        let started = try await disk.begin(book: book, series: series, listing: listing, account: account)
        try await disk.remove(book.id, account: account)
        do {
            _ = try await disk.savePage(Data("late".utf8), id: book.id, index: 0, generation: started.generation, account: account)
            XCTFail("Late response must be rejected")
        } catch { XCTAssertEqual(error as? OfflineError, .staleTransfer) }
        let records = try await disk.downloads(account: account)
        XCTAssertTrue(records.isEmpty)
    }

    func testRestartedTransferRejectsOldGenerationAndPrematureCompletion() async throws {
        let disk = store()
        let old = try await disk.begin(book: book, series: series, listing: listing, account: account)
        let new = try await disk.begin(book: book, series: series, listing: listing, account: account)
        do {
            _ = try await disk.savePage(Data("late".utf8), id: book.id, index: 0, generation: old.generation, account: account)
            XCTFail("Old generation must be rejected")
        } catch { XCTAssertEqual(error as? OfflineError, .staleTransfer) }
        do { _ = try await disk.finish(book.id, generation: new.generation, account: account); XCTFail("Missing pages") }
        catch { XCTAssertEqual(error as? OfflineError, .incomplete) }
    }

    func testLowDiskSpaceRejectsAdmissionAndEachPageCommit() async throws {
        do { _ = try await download(store(free: 20)); XCTFail("Disk full") }
        catch { XCTAssertEqual(error as? OfflineError, .lowSpace) }
        let first = store()
        let started = try await first.begin(book: book, series: series, listing: listing, account: account)
        let full = store(free: OfflineStore.minimumFreeBytes + 1)
        do {
            _ = try await full.savePage(Data("page".utf8), id: book.id, index: 0, generation: started.generation, account: account)
            XCTFail("Must recheck disk at commit")
        } catch { XCTAssertEqual(error as? OfflineError, .lowSpace) }
        let partial = try await first.record(book.id, account: account)
        XCTAssertEqual(partial?.downloadedPages, 0)
    }

    func testCorruptPageIsDetectedAndFetchedAgainOnResume() async throws {
        let disk = store()
        _ = try await download(disk)
        let file = root.appendingPathComponent(account.key).appendingPathComponent(book.id).appendingPathComponent("1.page")
        try Data("broken".utf8).write(to: file)
        do { _ = try await disk.page(book.id, index: 1, account: account); XCTFail("Hash must catch same-size corruption") }
        catch { XCTAssertEqual(error as? OfflineError, .incomplete) }
        var requests: [Int] = []
        let done = try await OfflineTransfer.run(store: disk, account: account, book: book, series: series, listing: listing,
            fetchPage: { requests.append($0); return Data("page-\($0)".utf8) }, progress: { _ in })
        XCTAssertTrue(done.complete); XCTAssertEqual(requests, [1])
    }

    func testChangedPageCountDoesNotMixReleases() async throws {
        let disk = store()
        _ = try await download(disk)
        let changed = ReaderBook(id: book.id, seriesTitle: book.seriesTitle, title: book.title, pageCount: 4,
            direction: book.direction, mode: book.mode, previousId: nil, nextId: nil, seriesId: book.seriesId)
        do {
            _ = try await disk.begin(book: changed, series: series, listing: listing, account: account)
            XCTFail("Changed source must not reuse pages")
        } catch { XCTAssertEqual(error as? OfflineError, .changedBook) }
    }

    func testPathTraversalInvalidPageAndMismatchedSeriesAreRejected() async throws {
        let disk = store()
        do { try await disk.remove("../outside", account: account); XCTFail("Traversal") }
        catch { XCTAssertEqual(error as? ReaderError, .invalidIdentifier) }
        do {
            _ = try await disk.begin(book: book, series: DemoCatalog.series[1], listing: listing, account: account)
            XCTFail("Wrong series")
        } catch { XCTAssertEqual(error as? ReaderError, .invalidIdentifier) }
        let started = try await disk.begin(book: book, series: series, listing: listing, account: account)
        for (index, data) in [(-1, Data("page".utf8)), (3, Data("page".utf8)), (0, Data())] {
            do {
                _ = try await disk.savePage(data, id: book.id, index: index, generation: started.generation, account: account)
                XCTFail("Invalid page")
            } catch { XCTAssertEqual(error as? OfflineError, .invalidPage) }
        }
    }

    func testOfflineBookmarksAndCoversSurviveRelaunchAndStayAccountScoped() async throws {
        let disk = store()
        _ = try await download(disk)
        let saved = ReaderBookmark(seriesId: series.id, seriesTitle: series.title, bookId: book.id,
            label: listing.label, pageIndex: 1, updatedAt: "today")
        try await disk.saveBookmarks([saved], account: account)
        try await disk.saveCover(Data("thumbnail".utf8), seriesID: series.id, account: account)
        let reopened = store()
        let bookmarks = try await reopened.bookmarks(account: account)
        let cover = try await reopened.cover(seriesID: series.id, account: account)
        let records = try await reopened.downloads(account: account)
        XCTAssertEqual(bookmarks, [saved]); XCTAssertEqual(cover, Data("thumbnail".utf8))
        XCTAssertEqual(records.count, 1, "Metadata must not become a book")
        let other = OfflineAccount(instance: "other", username: "reader")
        let foreign = try await reopened.bookmarks(account: other)
        let foreignCover = try await reopened.cover(seriesID: series.id, account: other)
        XCTAssertTrue(foreign.isEmpty); XCTAssertNil(foreignCover)
        let folder = root.appendingPathComponent(account.key).appendingPathComponent(".metadata")
        let mode = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("bookmarks-sync.json").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testOfflineScopeContainsOnlyCompletedSeriesAndTheirBookmarks() async throws {
        let disk = store()
        let completed = try await download(disk)
        let otherSeries = DemoCatalog.series[1], otherListing = try DemoCatalog.books(for: DemoCatalog.series[1].id)[0]
        let partial = try await disk.begin(book: DemoCatalog.book(otherListing.id), series: otherSeries,
            listing: otherListing, account: account)
        let bookmarks = [
            ReaderBookmark(seriesId: series.id, seriesTitle: series.title, bookId: "not-downloaded", label: "Chapter 2", pageIndex: 1, updatedAt: "today"),
            ReaderBookmark(seriesId: otherSeries.id, seriesTitle: otherSeries.title, bookId: partial.id, label: "Chapter 1", pageIndex: 0, updatedAt: "today")]
        XCTAssertEqual(OfflineLibrary.series([partial, completed]).map(\.id), [series.id])
        XCTAssertEqual(OfflineLibrary.bookmarks(bookmarks, downloads: [partial, completed]), [bookmarks[0]])
        XCTAssertEqual(OfflineLibrary.books(seriesID: series.id, downloads: [partial, completed]).map(\.id), [book.id])
        XCTAssertTrue(OfflineLibrary.bookmarks(bookmarks, downloads: []).isEmpty)
    }

    func testRemoveSeriesDeletesPartialAndCompleteBooksButKeepsOtherSeriesAndBookmarks() async throws {
        let disk = store()
        let done = try await download(disk)
        let otherSeries = DemoCatalog.series[1], otherListing = try DemoCatalog.books(for: DemoCatalog.series[1].id)[0]
        let partial = try await disk.begin(book: DemoCatalog.book(otherListing.id), series: otherSeries,
            listing: otherListing, account: account)
        let bookmark = ReaderBookmark(seriesId: series.id, seriesTitle: series.title, bookId: book.id,
            label: listing.label, pageIndex: 1, updatedAt: "today")
        try await disk.saveBookmarks([bookmark], account: account)
        try await disk.saveCover(Data("cover".utf8), seriesID: series.id, account: account)
        try await disk.removeSeries(series.id, account: account)
        let remaining = try await disk.downloads(account: account)
        let bookmarks = try await disk.bookmarks(account: account)
        let removedCover = try await disk.cover(seriesID: series.id, account: account)
        XCTAssertEqual(remaining.map(\.id), [partial.id]); XCTAssertEqual(bookmarks, [bookmark]); XCTAssertNil(removedCover)
        do {
            _ = try await disk.savePage(Data("late".utf8), id: done.id, index: 0, generation: done.generation, account: account)
            XCTFail("Late transfer must not recreate a removed series")
        } catch { XCTAssertEqual(error as? OfflineError, .staleTransfer) }
        try await disk.removeSeries(otherSeries.id, account: account)
        let empty = try await disk.downloads(account: account)
        XCTAssertTrue(empty.isEmpty)
    }
}
