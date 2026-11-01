import Foundation
import CryptoKit

public enum OfflineError: LocalizedError, Equatable {
    case notDownloaded, incomplete, lowSpace, invalidPage, changedBook, staleTransfer, invalidStorage
    public var errorDescription: String? {
        switch self {
        case .notDownloaded: return L10n.text("Questo libro non è scaricato sul dispositivo.")
        case .incomplete: return L10n.text("Download incompleto o danneggiato. Ricollegati e riprendi il download.")
        case .lowSpace: return L10n.text("Spazio insufficiente. Libera spazio sul dispositivo e riprova.")
        case .invalidPage: return L10n.text("Pagina non valida o troppo grande per il download.")
        case .changedBook: return L10n.text("Il libro sul server è cambiato. Rimuovi la copia locale e scaricalo di nuovo.")
        case .staleTransfer: return L10n.text("Il download è stato annullato.")
        case .invalidStorage: return L10n.text("Impossibile aprire l’archivio dei download sul dispositivo.")
        }
    }
}

/// LAN and HTTPS for the same instance share downloads; different accounts do not.
/// Neither passwords nor server URLs are saved in the download manifest.
public struct OfflineAccount: Equatable, Sendable {
    public let key: String
    public init(instance: String, username: String) {
        let data = try! JSONEncoder().encode([instance, username])
        key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct OfflineDownload: Codable, Identifiable, Sendable {
    public struct Page: Codable, Sendable { public let bytes: Int; public let sha256: String }
    public let schema: Int
    public let account: String
    public let generation: UUID
    public let book: ReaderBook
    public let series: LibrarySeries
    public let listing: LibraryBook
    public var pages: [String: Page]
    public var complete: Bool
    public let createdAt: Date
    public var id: String { book.id }
    public var downloadedPages: Int { pages.count }
    public var bytes: Int64 { pages.values.reduce(0) { $0 + Int64($1.bytes) } }
}

/// Actor serializes disk changes. A generation fences late responses after a delete,
/// account switch or replacement transfer. Page writes and manifests are atomic.
public actor OfflineStore {
    public static let maxPageBytes = 64 * 1024 * 1024
    public static let minimumFreeBytes: Int64 = 256 * 1024 * 1024
    private let root: URL
    private let freeBytes: @Sendable (URL) throws -> Int64
    private let reserve: Int64
    private let fm = FileManager.default

    public init(root: URL, reserve: Int64 = OfflineStore.minimumFreeBytes,
                freeBytes: @escaping @Sendable (URL) throws -> Int64 = OfflineStore.availableBytes) {
        self.root = root; self.reserve = reserve; self.freeBytes = freeBytes
    }

    public static func availableBytes(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = values.volumeAvailableCapacityForImportantUsage else { throw OfflineError.lowSpace }
        return bytes
    }

    private func directory(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw OfflineError.invalidStorage }
        var privateURL = url
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try privateURL.setResourceValues(attributes)
        #if os(iOS)
        // Background URLSession callbacks must commit while the screen is locked.
        // Still encrypted, device-local, and inaccessible before the first unlock.
        try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    private func accountURL(_ account: OfflineAccount) throws -> URL {
        try directory(root)
        let url = root.appendingPathComponent(account.key, isDirectory: true)
        try directory(url)
        return url
    }
    private func bookURL(_ id: String, account: OfflineAccount) throws -> URL {
        try accountURL(account).appendingPathComponent(Endpoint.identifier(id), isDirectory: true)
    }
    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func regularSize(_ url: URL) throws -> Int {
        let value = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard value.isRegularFile == true, value.isSymbolicLink != true, let size = value.fileSize else {
            throw OfflineError.incomplete
        }
        return size
    }
    private func read(_ id: String, account: OfflineAccount) throws -> OfflineDownload? {
        let folder = try bookURL(id, account: account)
        guard fm.fileExists(atPath: folder.path) else { return nil }
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw OfflineError.invalidStorage }
        let file = folder.appendingPathComponent("download.json")
        guard fm.fileExists(atPath: file.path) else { return nil }
        guard try regularSize(file) < 8 * 1024 * 1024 else { throw OfflineError.invalidStorage }
        let record = try JSONDecoder().decode(OfflineDownload.self, from: Data(contentsOf: file))
        guard record.schema == 1, record.account == account.key, record.id == id,
              record.listing.id == id, record.book.seriesId == record.series.id,
              (1...20_000).contains(record.book.pageCount),
              record.pages.allSatisfy({ key, page in
                  guard let index = Int(key), String(index) == key else { return false }
                  return (0..<record.book.pageCount).contains(index) && page.bytes > 0 && page.bytes <= Self.maxPageBytes
              }) else { throw OfflineError.invalidStorage }
        return record
    }
    private func persist(_ record: OfflineDownload, account: OfflineAccount) throws {
        try write(JSONEncoder().encode(record), to: bookURL(record.id, account: account).appendingPathComponent("download.json"))
    }
    public func downloads(account: OfflineAccount) throws -> [OfflineDownload] {
        let folder = try accountURL(account)
        return try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".metadata" }
            .compactMap { try read($0.lastPathComponent, account: account) }
            .sorted { $0.createdAt > $1.createdAt }
    }
    public func record(_ id: String, account: OfflineAccount) throws -> OfflineDownload? {
        try read(id, account: account)
    }
    private func metadataURL(_ name: String, account: OfflineAccount) throws -> URL {
        let folder = try accountURL(account).appendingPathComponent(".metadata", isDirectory: true)
        try directory(folder)
        return folder.appendingPathComponent(name)
    }
    public func backgroundQueue(account: OfflineAccount) throws -> BackgroundDownloadQueue {
        let file = try metadataURL("background-queue.json", account: account)
        guard fm.fileExists(atPath: file.path) else { return BackgroundDownloadQueue(account: account) }
        guard try regularSize(file) <= 32 * 1024 * 1024 else { throw OfflineError.invalidStorage }
        let queue = try JSONDecoder().decode(BackgroundDownloadQueue.self, from: Data(contentsOf: file))
        try queue.validate(for: account)
        return queue
    }
    public func saveBackgroundQueue(_ queue: BackgroundDownloadQueue, account: OfflineAccount) throws {
        try queue.validate(for: account)
        let data = try JSONEncoder().encode(queue)
        guard data.count <= 32 * 1024 * 1024 else { throw OfflineError.invalidStorage }
        try write(data, to: metadataURL("background-queue.json", account: account))
    }
    public func saveBookmarks(_ bookmarks: [ReaderBookmark], account: OfflineAccount) throws {
        let data = try JSONEncoder().encode(bookmarks)
        guard data.count <= 8 * 1024 * 1024 else { throw OfflineError.invalidStorage }
        try checkSpace(for: data.count)
        try write(data, to: metadataURL("bookmarks.json", account: account))
    }
    public func bookmarks(account: OfflineAccount) throws -> [ReaderBookmark] {
        let file = try metadataURL("bookmarks.json", account: account)
        guard fm.fileExists(atPath: file.path) else { return [] }
        guard try regularSize(file) <= 8 * 1024 * 1024 else { throw OfflineError.invalidStorage }
        return try JSONDecoder().decode([ReaderBookmark].self, from: Data(contentsOf: file))
    }
    public func saveCover(_ data: Data, seriesID: String, account: OfflineAccount) throws {
        guard !data.isEmpty, data.count <= 2 * 1024 * 1024 else { throw OfflineError.invalidPage }
        try checkSpace(for: data.count)
        try write(data, to: metadataURL("cover-\(try Endpoint.identifier(seriesID)).jpg", account: account))
    }
    public func cover(seriesID: String, account: OfflineAccount) throws -> Data? {
        let file = try metadataURL("cover-\(try Endpoint.identifier(seriesID)).jpg", account: account)
        guard fm.fileExists(atPath: file.path) else { return nil }
        guard try regularSize(file) <= 2 * 1024 * 1024 else { throw OfflineError.invalidStorage }
        return try Data(contentsOf: file)
    }
    public func removeSeries(_ id: String, account: OfflineAccount) throws {
        for record in try downloads(account: account) where record.series.id == id {
            try remove(record.id, account: account)
        }
        let cover = try metadataURL("cover-\(try Endpoint.identifier(id)).jpg", account: account)
        if fm.fileExists(atPath: cover.path) { try fm.removeItem(at: cover) }
    }
    public func checkSpace(for bytes: Int = OfflineStore.maxPageBytes) throws {
        try directory(root)
        // Leave room for the atomic replacement as well as the page being fetched.
        guard bytes >= 0, try freeBytes(root) >= reserve + Int64(bytes) * 2 else { throw OfflineError.lowSpace }
    }
    public func begin(book: ReaderBook, series: LibrarySeries, listing: LibraryBook,
                      account: OfflineAccount, generation: UUID = UUID()) throws -> OfflineDownload {
        try Task.checkCancellation()
        guard book.id == listing.id, book.seriesId == series.id, (1...20_000).contains(book.pageCount) else {
            throw ReaderError.invalidIdentifier
        }
        let old = try read(book.id, account: account)
        if let old, old.book.pageCount != book.pageCount || old.book.seriesId != book.seriesId {
            throw OfflineError.changedBook
        }
        try checkSpace(for: 64 * 1024)
        try directory(bookURL(book.id, account: account))
        let record = OfflineDownload(schema: 1, account: account.key, generation: generation, book: book,
            series: series, listing: listing, pages: old?.pages ?? [:], complete: false, createdAt: old?.createdAt ?? Date())
        try persist(record, account: account)
        return record
    }
    private func current(_ id: String, generation: UUID, account: OfflineAccount) throws -> OfflineDownload {
        guard let record = try read(id, account: account), record.generation == generation else { throw OfflineError.staleTransfer }
        return record
    }
    private func pageData(_ record: OfflineDownload, index: Int, account: OfflineAccount) throws -> Data {
        guard (0..<record.book.pageCount).contains(index), let info = record.pages[String(index)] else { throw OfflineError.incomplete }
        let file = try bookURL(record.id, account: account).appendingPathComponent("\(index).page")
        guard try regularSize(file) == info.bytes else { throw OfflineError.incomplete }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard Self.hash(data) == info.sha256 else { throw OfflineError.incomplete }
        return data
    }
    public func hasPage(_ id: String, index: Int, generation: UUID, account: OfflineAccount) throws -> Bool {
        let record = try current(id, generation: generation, account: account)
        return (try? pageData(record, index: index, account: account)) != nil
    }
    public func savePage(_ data: Data, id: String, index: Int, generation: UUID, account: OfflineAccount) throws -> OfflineDownload {
        try Task.checkCancellation()
        var record = try current(id, generation: generation, account: account)
        guard (0..<record.book.pageCount).contains(index), !data.isEmpty, data.count <= Self.maxPageBytes else { throw OfflineError.invalidPage }
        try checkSpace(for: data.count)
        try write(data, to: bookURL(id, account: account).appendingPathComponent("\(index).page"))
        record.pages[String(index)] = .init(bytes: data.count, sha256: Self.hash(data))
        record.complete = false
        try persist(record, account: account)
        return record
    }
    public func finish(_ id: String, generation: UUID, account: OfflineAccount) throws -> OfflineDownload {
        try Task.checkCancellation()
        var record = try current(id, generation: generation, account: account)
        guard record.pages.count == record.book.pageCount else { throw OfflineError.incomplete }
        for index in 0..<record.book.pageCount {
            let path = try bookURL(id, account: account).appendingPathComponent("\(index).page")
            guard try regularSize(path) == record.pages[String(index)]?.bytes else { throw OfflineError.incomplete }
        }
        record.complete = true
        try persist(record, account: account)
        return record
    }
    public func book(_ id: String, account: OfflineAccount) throws -> ReaderBook? {
        guard let record = try read(id, account: account), record.complete else { return nil }
        return record.book
    }
    public func page(_ id: String, index: Int, account: OfflineAccount) throws -> Data? {
        guard var record = try read(id, account: account), record.complete else { return nil }
        do { return try pageData(record, index: index, account: account) }
        catch {
            record.complete = false
            try persist(record, account: account)
            throw OfflineError.incomplete
        }
    }
    public func remove(_ id: String, account: OfflineAccount) throws {
        let folder = try bookURL(id, account: account)
        if fm.fileExists(atPath: folder.path) { try fm.removeItem(at: folder) }
    }
    public func removeAll(account: OfflineAccount) throws {
        try fm.removeItem(at: accountURL(account))
    }
    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum OfflineTransfer {
    /// One page at a time; completed pages survive cancellation and process termination.
    /// No completion marker is published until all pages have been persisted.
    public static func run(store: OfflineStore, account: OfflineAccount, book: ReaderBook,
                           series: LibrarySeries, listing: LibraryBook,
                           fetchPage: (Int) async throws -> Data,
                           progress: (OfflineDownload) async -> Void) async throws -> OfflineDownload {
        let initial = try await store.begin(book: book, series: series, listing: listing, account: account)
        await progress(initial)
        for index in 0..<book.pageCount {
            try Task.checkCancellation()
            if try await store.hasPage(book.id, index: index, generation: initial.generation, account: account) { continue }
            try await store.checkSpace()
            let data = try await fetchPage(index)
            try Task.checkCancellation()
            let record = try await store.savePage(data, id: book.id, index: index, generation: initial.generation, account: account)
            await progress(record)
        }
        let finished = try await store.finish(book.id, generation: initial.generation, account: account)
        await progress(finished)
        return finished
    }
}
