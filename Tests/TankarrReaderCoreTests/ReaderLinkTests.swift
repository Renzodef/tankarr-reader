import Foundation
import XCTest
@testable import TankarrReaderCore

final class ReaderLinkTests: XCTestCase {
    func testSeriesLinkOpensSeriesWithoutSelectingAVolume() {
        XCTAssertEqual(ReaderLink(url: URL(string: "tankarr-reader://series/s%201")!), .series(id: "s 1"))
        XCTAssertEqual(ReaderLink(url: URL(string: "https://tankarr.example.com/#series=s1")!), .series(id: "s1"))
        XCTAssertNil(ReaderLink(url: URL(string: "tankarr-reader://series/a/b")!))
        XCTAssertNil(ReaderLink(url: URL(string: "https://tankarr.example.com/#series=")!))
    }

    func testWebReaderLinkOpensBookAtOneBasedPage() {
        let url = URL(string: "https://tankarr.example.com/#book=manual-abc123&page=3")!
        XCTAssertEqual(ReaderLink(url: url), ReaderLink(bookID: "manual-abc123", pageIndex: 2))
    }

    func testMissingOrInvalidPageOpensFromStart() {
        XCTAssertEqual(ReaderLink(url: URL(string: "https://tankarr.example.com/#book=b1")!),
                       ReaderLink(bookID: "b1", pageIndex: nil))
        XCTAssertEqual(ReaderLink(url: URL(string: "https://tankarr.example.com/#book=b1&page=0")!),
                       ReaderLink(bookID: "b1", pageIndex: nil))
        XCTAssertEqual(ReaderLink(url: URL(string: "https://tankarr.example.com/#book=b1&page=x")!),
                       ReaderLink(bookID: "b1", pageIndex: nil))
    }

    func testPercentEncodedBookIDIsDecoded() {
        let url = URL(string: "https://tankarr.example.com/#book=a%20b&page=1")!
        XCTAssertEqual(ReaderLink(url: url), .book(id: "a b", pageIndex: 0))
    }

    func testLinksWithoutBookAreIgnored() {
        XCTAssertNil(ReaderLink(url: URL(string: "https://tankarr.example.com/")!))
        XCTAssertNil(ReaderLink(url: URL(string: "https://tankarr.example.com/#book=")!))
        XCTAssertNil(ReaderLink(url: URL(string: "https://tankarr.example.com/#page=2")!))
    }

    func testAppSchemeLinkOpensBookAtOneBasedPage() {
        XCTAssertEqual(ReaderLink(url: URL(string: "tankarr-reader://book/manual-abc123?page=3")!),
                       ReaderLink(bookID: "manual-abc123", pageIndex: 2))
        XCTAssertEqual(ReaderLink(url: URL(string: "TANKARR-READER://book/b1")!),
                       ReaderLink(bookID: "b1", pageIndex: nil))
        XCTAssertEqual(ReaderLink(url: URL(string: "tankarr-reader://book/a%20b?page=0")!),
                       ReaderLink(bookID: "a b", pageIndex: nil))
    }

    func testAppSchemeLinksWithoutBookAreIgnored() {
        XCTAssertNil(ReaderLink(url: URL(string: "tankarr-reader://book/")!))
        XCTAssertNil(ReaderLink(url: URL(string: "tankarr-reader://series/")!))
        XCTAssertNil(ReaderLink(url: URL(string: "tankarr-reader://book/a/b")!))
        XCTAssertNil(ReaderLink(url: URL(string: "other-app://book/b1")!))
    }

    func testOnlyWebLinksAreAccepted() {
        XCTAssertNil(ReaderLink(url: URL(string: "file:///tmp/#book=b1")!))
        XCTAssertNil(ReaderLink(url: URL(string: "javascript:alert(1)#book=b1")!))
    }
}
