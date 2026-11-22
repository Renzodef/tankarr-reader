import Foundation

/// A link to a series or to a book at an optional page.
public enum ReaderLink: Equatable, Sendable {
    case series(id: String)
    case book(id: String, pageIndex: Int?)

    public init(bookID: String, pageIndex: Int?) {
        self = .book(id: bookID, pageIndex: pageIndex)
    }

    public init?(url: URL) {
        if url.scheme?.lowercased() == ReaderLink.appScheme {
            self.init(appURL: url)
            return
        }
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
        guard let book = values["book"], !book.isEmpty else {
            guard let id = values["series"], !id.isEmpty else { return nil }
            self = .series(id: id)
            return
        }
        let page = values["page"].flatMap { Int($0) }
        self.init(bookID: book, pageIndex: page.flatMap { $0 >= 1 ? $0 - 1 : nil })
    }

    /// The app's own scheme, registered in Info.plist: `tankarr-reader://book/<id>?page=3`.
    /// iOS and macOS ask before opening it, so it works without Associated Domains.
    public static let appScheme = "tankarr-reader"

    private init?(appURL url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true)
        guard path.count == 1, let id = String(path[0]).removingPercentEncoding, !id.isEmpty else { return nil }
        switch parts.host?.lowercased() {
        case "series":
            self = .series(id: id)
        case "book":
            let page = parts.queryItems?.first(where: { $0.name == "page" })?.value.flatMap { Int($0) }
            self.init(bookID: id, pageIndex: page.flatMap { $0 >= 1 ? $0 - 1 : nil })
        default:
            return nil
        }
    }
}
