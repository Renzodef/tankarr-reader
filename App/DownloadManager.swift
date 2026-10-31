import SwiftUI
import UIKit
import ImageIO

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var items: [OfflineDownload] = []
    @Published private(set) var activeID: String?
    @Published private(set) var queuedIDs: Set<String> = []
    @Published private(set) var failures: [String: Error] = [:]
    @Published private(set) var storageError: Error?
    let store: OfflineStore
    private(set) var account: OfflineAccount?
    private var pending: [Request] = []
    private var task: Task<Void, Never>?
    private var changingAccount = false
    private struct Request {
        let series: LibrarySeries
        let listing: LibraryBook
        let api: ReaderAPI?
        let demo: Bool
    }

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineDownloads", isDirectory: true)
        store = OfflineStore(root: root)
    }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    func item(_ id: String) -> OfflineDownload? { items.first { $0.id == id } }
    func isQueued(_ id: String) -> Bool { activeID == id || queuedIDs.contains(id) }

    func activate(_ account: OfflineAccount?) async {
        changingAccount = true
        await pauseAll()
        self.account = account; items = []; failures = [:]; storageError = nil
        await reload()
        changingAccount = false
    }
    func reload() async {
        guard let account else { return }
        do {
            let records = try await store.downloads(account: account)
            guard self.account == account else { return }
            items = records; storageError = nil
        } catch { if self.account == account { storageError = error } }
    }
    func enqueue(series: LibrarySeries, books: [LibraryBook], api: ReaderAPI?, demo: Bool) {
        guard !changingAccount, account != nil, api != nil || demo else { return }
        for book in books where !isQueued(book.id) && item(book.id)?.complete != true {
            pending.append(Request(series: series, listing: book, api: api, demo: demo))
            queuedIDs.insert(book.id); failures[book.id] = nil
        }
        launchNext()
    }
    private func update(_ record: OfflineDownload) {
        items.removeAll { $0.id == record.id }; items.append(record)
        items.sort { $0.createdAt > $1.createdAt }
    }
    private func launchNext() {
        guard task == nil, !pending.isEmpty, let account, !changingAccount else { return }
        let request = pending.removeFirst()
        let id = request.listing.id
        queuedIDs.remove(id); activeID = id
        task = Task {
            defer { activeID = nil; task = nil; launchNext() }
            do {
                let book: ReaderBook
                if request.demo { book = try DemoCatalog.book(id) }
                else {
                    guard let api = request.api else { throw ReaderError.unavailable(0) }
                    book = try await api.get("/v1/books/\(try Endpoint.identifier(id))")
                }
                _ = try await OfflineTransfer.run(store: store, account: account, book: book,
                    series: request.series, listing: request.listing, fetchPage: { index in
                        let data: Data
                        if request.demo {
                            guard let png = DemoArtwork.page(try DemoCatalog.page(id, at: index)).pngData() else { throw OfflineError.invalidPage }
                            data = png
                        } else {
                            guard let api = request.api else { throw ReaderError.unavailable(0) }
                            data = try await api.downloadPage(book: id, index: index)
                        }
                        // Reject HTML/error responses and truncated images before marking a page saved.
                        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                              CGImageSourceGetStatus(source) == .statusComplete,
                              CGImageSourceGetCount(source) > 0,
                              CGImageSourceCopyPropertiesAtIndex(source, 0, nil) != nil else { throw OfflineError.invalidPage }
                        return data
                    }, progress: { record in self.update(record) })
            } catch {
                if !Task.isCancelled {
                    failures[id] = error
                    // A network/disk failure pauses the whole queue: no unbounded retry storm.
                    pending = []; queuedIDs = []
                }
            }
        }
    }
    func pause(_ id: String) {
        pending.removeAll { $0.listing.id == id }; queuedIDs.remove(id)
        if activeID == id { task?.cancel() }
    }
    func pauseAll() async {
        pending = []; queuedIDs = []
        let running = task
        running?.cancel()
        await running?.value
    }
    func remove(_ id: String) async {
        guard let account else { return }
        pause(id)
        if activeID == id { await task?.value }
        do {
            try await store.remove(id, account: account)
            items.removeAll { $0.id == id }; failures[id] = nil; storageError = nil
        } catch { storageError = error }
    }
    func removeAll() async throws {
        await pauseAll()
        guard let account else { return }
        try await store.removeAll(account: account)
        items = []; failures = [:]; storageError = nil
    }
}
