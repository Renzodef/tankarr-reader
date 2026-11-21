import Foundation
import XCTest
@testable import TankarrReaderCore

final class ReaderLinkTests: XCTestCase {
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
        XCTAssertEqual(ReaderLink(url: url)?.bookID, "a b")
    }

    func testLinksWithoutBookAreIgnored() {
        XCTAssertNil(ReaderLink(url: URL(string: "https://tankarr.example.com/")!))
        XCTAssertNil(ReaderLink(url: URL(string: "https://tankarr.example.com/#book=")!))
        XCTAssertNil(ReaderLink(url: URL(string: "https://tankarr.example.com/#page=2")!))
    }

    func testOnlyWebLinksAreAccepted() {
        XCTAssertNil(ReaderLink(url: URL(string: "file:///tmp/#book=b1")!))
        XCTAssertNil(ReaderLink(url: URL(string: "javascript:alert(1)#book=b1")!))
    }
}
