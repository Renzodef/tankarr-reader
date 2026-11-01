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
}
