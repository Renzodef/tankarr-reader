import Foundation
import XCTest
@testable import TankarrReaderCore

final class ReaderNavigationTests: XCTestCase {
    private func book(previous: String? = "first", next: String? = "third") -> ReaderBook {
        ReaderBook(id: "second", seriesTitle: "Series", title: "Chapter 2", pageCount: 8,
                   direction: "rtl", mode: "manga", previousId: previous, nextId: next, seriesId: "series")
    }
    func testCrossingChapterStartsNextAtFirstAndPreviousAtLast() {
        XCTAssertEqual(ReaderNavigation.step(book: book(), page: 7, forward: true, offline: false, downloaded: []),
                       .chapter("third", lastPage: false))
        XCTAssertEqual(ReaderNavigation.step(book: book(), page: 0, forward: false, offline: false, downloaded: []),
                       .chapter("first", lastPage: true))
        XCTAssertEqual(ReaderNavigation.step(book: book(), page: 6, forward: true, offline: true, downloaded: []), .page(7))
    }
    func testOfflineNeverSkipsAnUndownloadedNeighbour() {
        XCTAssertEqual(ReaderNavigation.step(book: book(), page: 7, forward: true, offline: true, downloaded: ["fourth"]),
                       .unavailable(.nextNotDownloaded))
        XCTAssertEqual(ReaderNavigation.step(book: book(), page: 0, forward: false, offline: true, downloaded: ["third"]),
                       .unavailable(.previousNotDownloaded))
        XCTAssertEqual(ReaderNavigation.step(book: book(), page: 7, forward: true, offline: true, downloaded: ["third"]),
                       .chapter("third", lastPage: false))
    }
    func testFirstAndLastChapterAndInvalidNeighbours() {
        XCTAssertEqual(ReaderNavigation.step(book: book(previous: nil), page: 0, forward: false, offline: false, downloaded: []),
                       .unavailable(.beginning))
        for next in [nil, "second", "../elsewhere", ""] {
            XCTAssertEqual(ReaderNavigation.step(book: book(next: next), page: 7, forward: true, offline: false, downloaded: []),
                           .unavailable(.end))
        }
    }
    func testAutomaticOfflineOnlyForReachabilityErrors() {
        for code: URLError.Code in [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost] {
            XCTAssertTrue(OfflineConnectivity.isReachabilityFailure(URLError(code)))
        }
        for error: Error in [URLError(.cancelled), URLError(.serverCertificateUntrusted),
                             ReaderError.unauthorized, ReaderError.wrongServer, ReaderError.unavailable(503)] {
            XCTAssertFalse(OfflineConnectivity.isReachabilityFailure(error))
        }
    }

    func testOldDownloadedNeighboursCannotWrapFromTheLastChapterToAPrologueOrFirstChapter() {
        func metadata(_ id: String, _ title: String) -> ReaderBook {
            ReaderBook(id: id, seriesTitle: "Series", title: title, pageCount: 3,
                direction: "rtl", mode: "manga", previousId: nil, nextId: nil, seriesId: "series")
        }
        let last = metadata("last", "Chapter 300")
        XCTAssertFalse(ReaderNavigation.allowsTransition(from: last, to: metadata("first", "Capitolo 1"), forward: true))
        XCTAssertFalse(ReaderNavigation.allowsTransition(from: last, to: metadata("prologue", "Prologue 1"), forward: true))
        let listing = LibraryBook(id: "prologue", label: "Libro", title: "Prologue 1", volume: "1", chapter: "", unit: "chapter", language: "en")
        XCTAssertFalse(ReaderNavigation.allowsTransition(from: last, to: metadata("prologue", "Volume 1"), forward: true, candidate: listing),
                       "Old cached book titles may hide that a file is a prologue")
        XCTAssertTrue(ReaderNavigation.allowsTransition(from: metadata("two", "Chapter 2"), to: last, forward: true))
        XCTAssertTrue(ReaderNavigation.allowsTransition(from: last, to: metadata("two", "Chapter 2"), forward: false))
        XCTAssertTrue(ReaderNavigation.allowsTransition(from: metadata("prologue", "Prologue 1"), to: metadata("first", "Chapter 1"), forward: true))
    }

    func testArrowKeysFollowTheReadingDirection() {
        XCTAssertEqual(ReaderNavigation.keyStep(.right, vertical: false, rightToLeft: false), 1)
        XCTAssertEqual(ReaderNavigation.keyStep(.left, vertical: false, rightToLeft: false), -1)
        // Manga: the next page is to the left.
        XCTAssertEqual(ReaderNavigation.keyStep(.left, vertical: false, rightToLeft: true), 1)
        XCTAssertEqual(ReaderNavigation.keyStep(.right, vertical: false, rightToLeft: true), -1)
        XCTAssertEqual(ReaderNavigation.keyStep(.down, vertical: true, rightToLeft: false), 1)
        XCTAssertEqual(ReaderNavigation.keyStep(.up, vertical: true, rightToLeft: false), -1)
    }

    func testArrowKeysAcrossTheReadingAxisDoNothing() {
        XCTAssertNil(ReaderNavigation.keyStep(.up, vertical: false, rightToLeft: false))
        XCTAssertNil(ReaderNavigation.keyStep(.down, vertical: false, rightToLeft: true))
        XCTAssertNil(ReaderNavigation.keyStep(.left, vertical: true, rightToLeft: false))
        XCTAssertNil(ReaderNavigation.keyStep(.right, vertical: true, rightToLeft: true))
    }
}
