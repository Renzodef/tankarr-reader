import Foundation

/// A link to one book in the web reader, such as `https://host/#book=<id>&page=3`.
///
/// Safari's "Open in app" banner passes the page address to the app, so the app
/// can open the same book. The page number in the link is 1-based; `pageIndex`
/// is 0-based, and `nil` means "open where the reader would normally open".
public struct ReaderLink: Equatable, Sendable {
    public let bookID: String
    public let pageIndex: Int?

    public init(bookID: String, pageIndex: Int?) {
        self.bookID = bookID
        self.pageIndex = pageIndex
    }

    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment,
              !fragment.isEmpty else { return nil }
        // The fragment is read as `key=value&key=value`, decoding each part on its own.
        var values: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let field = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard field.count == 2, values[field[0]] == nil,
                  let value = field[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding else { continue }
            values[field[0]] = value
        }
        guard let book = values["book"], !book.isEmpty else { return nil }
        let page = values["page"].flatMap { Int($0) }
        self.init(bookID: book, pageIndex: page.flatMap { $0 >= 1 ? $0 - 1 : nil })
    }
}
