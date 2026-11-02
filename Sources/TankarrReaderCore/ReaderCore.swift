import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ReaderError: LocalizedError, Equatable {
    case invalidAddress, invalidIdentifier, invalidAccount, unauthorized, wrongServer, unavailable(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidAddress: return L10n.text("Usa un indirizzo HTTPS valido. HTTP è consentito solo per indirizzi della rete locale.")
        case .invalidIdentifier: return L10n.text("Identificativo della risorsa non valido.")
        case .invalidAccount: return L10n.text("Inserisci utente e password dell’account lettore.")
        case .unauthorized: return L10n.text("Utente o password del lettore non validi.")
        case .wrongServer: return L10n.text("Questo indirizzo non è il lettore Tankarr configurato.")
        case .unavailable(let status): return L10n.format("Risorsa non disponibile (%d). Riprova.", status)
        }
    }
}

public enum ConnectionMode: String, Codable, CaseIterable, Identifiable {
    case automatic, local, remote
    public var id: String { rawValue }
    public var label: String {
        switch self { case .automatic: return L10n.text("Automatico"); case .local: return L10n.text("Locale"); case .remote: return L10n.text("Remoto") }
    }
}

public struct ServerProfile: Codable, Equatable {
    public var localAddress: String
    public var remoteAddress: String
    public var username: String
    public var mode: ConnectionMode
    public var instanceID: String?
    public init(localAddress: String = "", remoteAddress: String = "", username: String = "", mode: ConnectionMode = .automatic, instanceID: String? = nil) {
        self.localAddress = localAddress; self.remoteAddress = remoteAddress
        self.username = username; self.mode = mode; self.instanceID = instanceID
    }
    public func candidates() throws -> [URL] {
        let raw: [String]
        switch mode {
        case .local: raw = [localAddress]
        case .remote: raw = [remoteAddress]
        case .automatic: raw = [localAddress, remoteAddress].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        var result: [URL] = []
        for value in raw {
            let endpoint = try Endpoint.validate(value)
            if !result.contains(endpoint) { result.append(endpoint) }
        }
        if result.isEmpty { throw ReaderError.invalidAddress }
        return result
    }
}

public enum Endpoint {
    public static func validate(_ input: String) throws -> URL {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(),
              !host.isEmpty, parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port == nil || (1...65535).contains(parts.port!),
              scheme == "https" || (scheme == "http" && localHost(host)),
              !parts.path.contains(".."), !parts.percentEncodedPath.lowercased().contains("%2f"),
              !parts.path.contains("\\") else { throw ReaderError.invalidAddress }
        parts.scheme = scheme
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        guard let url = parts.url else { throw ReaderError.invalidAddress }
        return url
    }
    private static func localHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host == "[::1]" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let numbers = parts.compactMap { part -> Int? in
            guard part.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(part), (0...255).contains(n), String(n) == part else { return nil }
            return n
        }
        guard numbers.count == 4 else { return false }
        return numbers[0] == 10 || numbers[0] == 127 ||
            (numbers[0] == 172 && (16...31).contains(numbers[1])) ||
            (numbers[0] == 192 && numbers[1] == 168)
    }
    public static func identifier(_ value: String) throws -> String {
        guard value.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]{0,159}$", options: .regularExpression) == value.startIndex..<value.endIndex else { throw ReaderError.invalidIdentifier }
        return value
    }
    public static func request(base: URL, path: String, username: String, password: String, timeout: TimeInterval = 35,
                               method: String = "GET", jsonBody: Data? = nil) throws -> URLRequest {
        _ = try validate(base.absoluteString)
        let id = "[A-Za-z0-9][A-Za-z0-9_.-]{0,159}"
        let readable = path.range(of: "^/v1/(status|library|bookmarks|follows|series/\(id)(/cover)?|books/\(id)(/pages/[0-9]+)?)$", options: .regularExpression) != nil
        let bookmark = path.range(of: "^/v1/series/\(id)/bookmark$", options: .regularExpression) != nil
        let follow = path.range(of: "^/v1/series/\(id)/follow$", options: .regularExpression) != nil
        let device = path.range(of: "^/v1/notifications/devices/[0-9a-fA-F-]{36}$", options: .regularExpression) != nil
        let writable = bookmark || follow || device
        guard (method == "GET" && readable && jsonBody == nil) ||
              (method == "PUT" && writable && jsonBody != nil) ||
              (method == "DELETE" && writable && jsonBody == nil) else { throw ReaderError.invalidIdentifier }
        guard !username.isEmpty, !password.isEmpty, !username.contains(":"), !username.contains("\n"), !username.contains("\r") else { throw ReaderError.invalidAccount }
        guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw ReaderError.invalidAddress }
        parts.path = parts.path + path
        guard let url = parts.url else { throw ReaderError.invalidAddress }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = jsonBody
        if jsonBody != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if method == "PUT" || method == "DELETE" {
            request.setValue("1", forHTTPHeaderField: "X-Tankarr-Reader")
        }
        let credential = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")
        return request
    }
}

public struct ReaderStatus: Decodable {
    public let name: String
    public let apiVersion: Int
    public let readOnly: Bool
    public let instanceId: String
    public let readingStateWritable: Bool?
    public let followingWritable: Bool?
    public let pushNotificationsAvailable: Bool?
}
public struct BookmarksResponse: Decodable { public let items: [ReaderBookmark] }
/// Tankarr stores one explicit reading bookmark per series, shared by its readers.
public struct ReaderBookmark: Codable, Identifiable, Hashable, Sendable {
    public let seriesId: String
    public let seriesTitle: String
    public let bookId: String
    public let label: String
    public let pageIndex: Int
    public let updatedAt: String
    public var id: String { seriesId }
    public init(seriesId: String, seriesTitle: String, bookId: String, label: String, pageIndex: Int, updatedAt: String) {
        self.seriesId = seriesId; self.seriesTitle = seriesTitle; self.bookId = bookId
        self.label = label; self.pageIndex = max(0, pageIndex); self.updatedAt = updatedAt
    }
}
public struct LibraryResponse: Decodable { public let items: [LibrarySeries] }
public struct LibrarySeries: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let authors: [String]
    public let language: String
    public let booksCount: Int
    public let coverPath: String
}
public struct BooksResponse: Decodable { public let books: [LibraryBook] }
public struct LibraryBook: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let title: String
    public let volume: String
    public let chapter: String
    public let unit: String
    public let language: String
}
public struct ReaderBook: Codable, Sendable {
    public let id: String
    public let seriesTitle: String
    public let title: String
    public let pageCount: Int
    public let direction: String
    public let mode: String
    public let previousId: String?
    public let nextId: String?
    public let seriesId: String?
    public let pageIndex: Int?
    public let bookmarked: Bool?
    public let bookmarkPageIndex: Int?
    public init(id: String, seriesTitle: String, title: String, pageCount: Int, direction: String, mode: String,
                previousId: String?, nextId: String?, seriesId: String? = nil, pageIndex: Int? = nil,
                bookmarked: Bool? = nil, bookmarkPageIndex: Int? = nil) {
        self.id = id; self.seriesTitle = seriesTitle; self.title = title; self.pageCount = pageCount
        self.direction = direction; self.mode = mode; self.previousId = previousId; self.nextId = nextId
        self.seriesId = seriesId; self.pageIndex = pageIndex; self.bookmarked = bookmarked; self.bookmarkPageIndex = bookmarkPageIndex
    }
}

public final class RefuseRedirects: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never carry the reader password to another endpoint.
    }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > OfflineStore.maxPageBytes || totalBytesExpectedToWrite > OfflineStore.maxPageBytes {
            downloadTask.cancel()
        }
    }
}

public final class ReaderAPI: @unchecked Sendable {
    public let base: URL
    private let username: String
    private let password: String
    private let session: URLSession
    public init(base: URL, username: String, password: String) {
        self.base = base; self.username = username; self.password = password
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config, delegate: RefuseRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func data(_ path: String, timeout: TimeInterval = 35, method: String = "GET", jsonBody: Data? = nil, reload: Bool = false) async throws -> Data {
        var request = try Endpoint.request(base: base, path: path, username: username, password: password,
                                           timeout: timeout, method: method, jsonBody: jsonBody)
        if reload { request.setValue("no-cache", forHTTPHeaderField: "Cache-Control") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReaderError.unavailable(0) }
        if http.statusCode == 401 { throw ReaderError.unauthorized }
        guard http.statusCode == 200 else { throw ReaderError.unavailable(http.statusCode) }
        return data
    }
    public func get<T: Decodable>(_ path: String, as type: T.Type = T.self, timeout: TimeInterval = 35, reload: Bool = false) async throws -> T {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: await data(path, timeout: timeout, reload: reload))
    }
    public func backgroundRequest(book: String, page: Int?) throws -> URLRequest {
        if let page, page < 0 { throw ReaderError.invalidIdentifier }
        let path = "/v1/books/\(try Endpoint.identifier(book))" + (page.map { "/pages/\($0)" } ?? "")
        var request = try Endpoint.request(base: base, path: path, username: username, password: password, timeout: 120)
        request.httpShouldHandleCookies = false
        return request
    }
    /// Download one page to a temporary file first; never buffer a whole volume.
    /// The same authenticated session refuses redirects and verifies TLS.
    public func downloadPage(book: String, index: Int) async throws -> Data {
        guard index >= 0 else { throw ReaderError.invalidIdentifier }
        let request = try Endpoint.request(base: base,
            path: "/v1/books/\(try Endpoint.identifier(book))/pages/\(index)",
            username: username, password: password, timeout: 90)
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ReaderError.unavailable(0) }
        if http.statusCode == 401 { throw ReaderError.unauthorized }
        guard http.statusCode == 200 else { throw ReaderError.unavailable(http.statusCode) }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= OfflineStore.maxPageBytes else { throw OfflineError.invalidPage }
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }
    public func saveBookmark(series: String, book: String, page: Int) async throws -> ReaderBookmark {
        guard page >= 0 else { throw ReaderError.invalidIdentifier }
        struct Body: Encodable { let book_id: String; let page_index: Int }
        let body = try JSONEncoder().encode(Body(book_id: try Endpoint.identifier(book), page_index: page))
        let responseData = try await data("/v1/series/\(try Endpoint.identifier(series))/bookmark", method: "PUT", jsonBody: body)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReaderBookmark.self, from: responseData)
    }
    public func removeBookmark(series: String) async throws {
        _ = try await data("/v1/series/\(try Endpoint.identifier(series))/bookmark", method: "DELETE")
    }
    public static func connect(profile: ServerProfile, password: String) async throws -> (ReaderAPI, ReaderStatus) {
        let candidates = try profile.candidates()
        var last: Error = ReaderError.invalidAddress
        for (offset, base) in candidates.enumerated() {
            try Task.checkCancellation()
            let api = ReaderAPI(base: base, username: profile.username, password: password)
            do {
                let status: ReaderStatus = try await api.get("/v1/status", timeout: offset < candidates.count - 1 ? 4 : 15)
                guard status.name == "Tankarr Reader", status.apiVersion == 1, status.readOnly,
                      profile.instanceID == nil || profile.instanceID == status.instanceId else { throw ReaderError.wrongServer }
                return (api, status)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if error as? ReaderError == .unauthorized || error as? ReaderError == .wrongServer { throw error }
                last = error
            }
        }
        throw last
    }
}
