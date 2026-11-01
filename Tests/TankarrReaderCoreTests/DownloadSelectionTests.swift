import XCTest
@testable import TankarrReaderCore

final class DownloadSelectionTests: XCTestCase {
    private func listing(_ id: String) -> LibraryBook {
        LibraryBook(id: id, label: id, title: "", volume: "", chapter: id, unit: "chapter", language: "en")
    }
    private func bookmark(_ book: String, series: String = "series") -> ReaderBookmark {
        ReaderBookmark(seriesId: series, seriesTitle: "Series", bookId: book, label: book, pageIndex: 2, updatedAt: "today")
    }
    func testInclusiveRangeUsesCatalogOrderAndSupportsSpecialAndDecimalChapters() {
        let books = ["1", "2", "2-5", "special", "10"].map(listing)
        XCTAssertEqual(DownloadSelection.range(books, from: "2", through: "special").map(\.id), ["2", "2-5", "special"])
        XCTAssertEqual(DownloadSelection.range(books, from: "10", through: "10").map(\.id), ["10"])
        XCTAssertEqual(DownloadSelection.range(books, from: "1", through: "10").count, 5)
    }
    func testInvalidOrReversedRangeNeverExpandsToAllBooks() {
        let books = ["1", "2", "10"].map(listing)
        XCTAssertTrue(DownloadSelection.range(books, from: "10", through: "2").isEmpty)
        XCTAssertTrue(DownloadSelection.range(books, from: "missing", through: "10").isEmpty)
        XCTAssertTrue(DownloadSelection.range(books, from: "1", through: "missing").isEmpty)
        XCTAssertTrue(DownloadSelection.range([], from: "1", through: "10").isEmpty)
    }
    func testBookmarkToEndIncludesBookAndRejectsStaleOrForeignBookmarks() {
        let books = ["1", "2", "10"].map(listing)
        XCTAssertEqual(DownloadSelection.fromBookmark(bookmark("2"), seriesID: "series", books: books).map(\.id), ["2", "10"])
        for saved in [nil, bookmark("missing"), bookmark("2", series: "other")] {
            XCTAssertTrue(DownloadSelection.fromBookmark(saved, seriesID: "series", books: books).isEmpty)
        }
    }
}
