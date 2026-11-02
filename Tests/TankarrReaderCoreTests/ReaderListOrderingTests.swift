import Foundation
import XCTest
@testable import TankarrReaderCore

final class ReaderListOrderingTests: XCTestCase {
    private func bookmark(_ id: String, title: String, at: String) -> ReaderBookmark {
        ReaderBookmark(seriesId: id, seriesTitle: title, bookId: "book-\(id)", label: "Chapter 1", pageIndex: 0, updatedAt: at)
    }

    private func item(_ id: String, series: String, title: String, chapter: String, at: Double,
                      unit: String = "chapter", volume: String = "", bookTitle: String? = nil, complete: Bool = true) -> OfflineDownload {
        let series = LibrarySeries(id: series, title: title, description: "", authors: [], language: "en", booksCount: 0, coverPath: "")
        let label = bookTitle ?? "Chapter \(chapter)"
        let listing = LibraryBook(id: id, label: label, title: label, volume: volume, chapter: chapter, unit: unit, language: "en")
        let book = ReaderBook(id: id, seriesTitle: title, title: label, pageCount: 1, direction: "ltr", mode: "paged", previousId: nil, nextId: nil)
        return OfflineDownload(schema: 1, account: "test", generation: UUID(), book: book, series: series,
            listing: listing, pages: [:], complete: complete, createdAt: Date(timeIntervalSince1970: at))
    }

    func testRecentBookmarksUseActualDatesIncludingTimezonesAndMalformedDates() {
        let values = [bookmark("a", title: "Alpha", at: "2026-11-02T10:30:00+02:00"),
                      bookmark("z", title: "Zeta", at: "2026-11-02T09:00:00.500Z"),
                      bookmark("bad", title: "Bad", at: "unknown")]
        XCTAssertEqual(ReaderListOrdering.bookmarks(values, sort: .recent).map(\.id), ["z", "a", "bad"])
        XCTAssertEqual(ReaderListOrdering.bookmarks(values, sort: .seriesTitle).map(\.id), ["a", "bad", "z"])
    }

    func testAlphabeticBookmarksHaveNaturalSeriesOrderAndStableTies() {
        let values = [bookmark("c", title: "Series 10", at: ""), bookmark("b", title: "Series 2", at: ""),
                      bookmark("a", title: "Series 2", at: "")]
        XCTAssertEqual(ReaderListOrdering.bookmarks(values, sort: .seriesTitle).map(\.id), ["a", "b", "c"])
    }

    func testDownloadsGroupByIdentityAndKeepNumericChapterOrderForBothChoices() {
        let values = [item("a10", series: "a", title: "Alpha", chapter: "10", at: 20),
                      item("a2", series: "a", title: "Alpha", chapter: "2", at: 10),
                      item("a25", series: "a", title: "Alpha", chapter: "2.5", at: 15),
                      item("z1", series: "z", title: "Zeta", chapter: "1", at: 30, complete: false)]
        let recent = ReaderListOrdering.downloadGroups(values, sort: .recent)
        XCTAssertEqual(recent.map(\.id), ["z", "a"])
        XCTAssertEqual(recent[1].items.map(\.id), ["a2", "a25", "a10"])
        XCTAssertFalse(recent[0].items[0].complete, "Paused/partial downloads must remain visible")
        let alphabetic = ReaderListOrdering.downloadGroups(values, sort: .seriesTitle)
        XCTAssertEqual(alphabetic.map(\.id), ["a", "z"])
        XCTAssertEqual(alphabetic[0].items.map(\.id), ["a2", "a25", "a10"])
    }

    func testProloguesVolumesAndIdenticallyNamedSeriesAreNotLostOrMerged() {
        let values = [item("chapter", series: "a", title: "Same title", chapter: "1", at: 1),
                      item("prologue", series: "a", title: "Same title", chapter: "0", at: 2, bookTitle: "Prologue 1"),
                      item("vol10", series: "b", title: "Same title", chapter: "", at: 3, unit: "volume", volume: "10", bookTitle: "Volume 10"),
                      item("vol2", series: "b", title: "Same title", chapter: "", at: 4, unit: "volume", volume: "2", bookTitle: "Volume 2")]
        let groups = ReaderListOrdering.downloadGroups(values, sort: .seriesTitle)
        XCTAssertEqual(groups.map(\.id), ["a", "b"])
        XCTAssertEqual(groups[0].items.map(\.id), ["prologue", "chapter"])
        XCTAssertEqual(groups[1].items.map(\.id), ["vol2", "vol10"])
        XCTAssertTrue(ReaderListOrdering.downloadGroups([], sort: .recent).isEmpty)
    }
}
