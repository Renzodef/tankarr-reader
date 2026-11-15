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
    @Published private(set) var backgroundPaused = false
    let store: OfflineStore
    private(set) var account: OfflineAccount?
    // Only the generated, network-free demonstration uses in-process work.
    private var pending: [DemoRequest] = []
    private var task: Task<Void, Never>?
    private var changingAccount = false
    private var removing = false
    private var background: BackgroundDownloads?
    private var backgroundJobs: [BackgroundDownloadJob] = []
    private struct DemoRequest {
        let series: LibrarySeries
        let listing: LibraryBook
    }

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineDownloads", isDirectory: true)
        store = OfflineStore(root: root)
    }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var canResumeBackgroundQueue: Bool { backgroundPaused && !backgroundJobs.isEmpty }
    func item(_ id: String) -> OfflineDownload? { items.first { $0.id == id } }
    func isQueued(_ id: String) -> Bool { activeID == id || (!backgroundPaused && queuedIDs.contains(id)) }
    /// Includes durable jobs waiting for metadata or paused by a network error.
    /// This is the selection order, not a claim that iOS transfers only one book.
    func queuePosition(_ id: String) -> Int? {
        if let index = backgroundJobs.firstIndex(where: { $0.listing.id == id }) { return index + 1 }
        if activeID == id { return 1 }
        return pending.firstIndex(where: { $0.listing.id == id }).map { $0 + (activeID == nil ? 1 : 2) }
    }
    func queuedCount(seriesID: String) -> Int {
        Set(backgroundJobs.filter { $0.series.id == seriesID }.map { $0.listing.id })
            .union(pending.filter { $0.series.id == seriesID }.map { $0.listing.id })
            .union(activeSeriesID == seriesID ? [activeID].compactMap { $0 } : []).count
    }
    func hasDownloads(seriesID: String) -> Bool {
        items.contains { $0.series.id == seriesID } || pending.contains { $0.series.id == seriesID }
            || activeSeriesID == seriesID || backgroundJobs.contains { $0.series.id == seriesID }
    }
    private var activeSeriesID: String?
    var hasDownloads: Bool { !items.isEmpty || activeID != nil || !queuedIDs.isEmpty || !backgroundJobs.isEmpty }

    func activate(_ account: OfflineAccount?) async {
        if self.account == account { await reload(); return }
        changingAccount = true
        await pauseAll(preserveQueue: true)
        background?.close()
        background = nil; backgroundJobs = []; backgroundPaused = false
        self.account = account; items = []; failures = [:]; storageError = nil
        await reload()
        changingAccount = false
    }
    func configureBackground(api: ReaderAPI, completion: (() -> Void)? = nil) async {
        guard let account else { completion?(); return }
        if background == nil {
            let engine = BackgroundDownloads(account: account, store: store, api: api)
            engine.changed = { [weak self] jobs, paused in
                guard let self, self.account == account else { return }
                self.backgroundJobs = jobs; self.backgroundPaused = paused
                self.activeID = paused ? nil : jobs.first?.listing.id
                self.activeSeriesID = paused ? nil : jobs.first?.series.id
                self.queuedIDs = Set(jobs.map { $0.listing.id }).subtracting([self.activeID].compactMap { $0 })
            }
            engine.saved = { [weak self] record in
                guard let self, self.account == account else { return }
                self.update(record)
                if record.complete { self.failures[record.id] = nil }
            }
            engine.failed = { [weak self] id, error in
                guard let self, self.account == account else { return }; self.failures[id] = error
            }
            background = engine
        }
        if let completion { background?.attachEvents(completion) }
        for job in backgroundJobs { failures[job.listing.id] = nil }
        await background?.start(api: api)
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
        guard !changingAccount, !removing, account != nil, api != nil || demo else { return }
        if !demo, let api {
            // Connected profiles configure their persistent session before the
            // UI can enqueue. Capture that owner, never a later account/session.
            guard let background else { return }
            for book in books { failures[book.id] = nil }
            background.enqueue(series: series, books: books)
            // Thumbnail is optional; the actual durable queue never waits on it.
            if let account {
                Task {
                    guard let data = try? await api.cover(series.id),
                          self.account == account, let image = UIImage(data: data),
                          let thumb = await image.byPreparingThumbnail(ofSize: CGSize(width: 360, height: 540)),
                          let jpeg = thumb.jpegData(compressionQuality: 0.8) else { return }
                    try? await store.saveCover(jpeg, seriesID: series.id, account: account)
                }
            }
            return
        }
        for book in books where !isQueued(book.id) && item(book.id)?.complete != true {
            pending.append(DemoRequest(series: series, listing: book))
            queuedIDs.insert(book.id); failures[book.id] = nil
        }
        launchNext()
    }
    private func update(_ record: OfflineDownload) {
        items.removeAll { $0.id == record.id }; items.append(record)
        items.sort { $0.createdAt > $1.createdAt }
    }
    private func launchNext() {
        guard task == nil, !pending.isEmpty, let account, !changingAccount, !removing else { return }
        let request = pending.removeFirst()
        let id = request.listing.id
        queuedIDs.remove(id); activeID = id; activeSeriesID = request.series.id
        task = Task {
            defer { activeID = nil; activeSeriesID = nil; task = nil; launchNext() }
            do {
                // A small cover travels with the download, so the offline grid
                // also works after a cold launch. Cover failure is non-fatal.
                if (try? await store.cover(seriesID: request.series.id, account: account)) == nil {
                    let source = DemoArtwork.cover(request.series)
                    let thumb = await source.byPreparingThumbnail(ofSize: CGSize(width: 360, height: 540)) ?? source
                    if let data = thumb.jpegData(compressionQuality: 0.8) {
                        try? await store.saveCover(data, seriesID: request.series.id, account: account)
                    }
                }
                try Task.checkCancellation()
                let book = try DemoCatalog.book(id)
                _ = try await OfflineTransfer.run(store: store, account: account, book: book,
                    series: request.series, listing: request.listing, fetchPage: { index in
                        guard let data = DemoArtwork.page(try DemoCatalog.page(id, at: index)).pngData() else { throw OfflineError.invalidPage }
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
                    // Local demo generation failed. Real downloads retain their
                    // complete selection in BackgroundDownloads instead.
                    pending = []; queuedIDs = []
                }
            }
        }
    }
    func pause(_ id: String) {
        if let background { Task { await background.pause(book: id) }; return }
        pending.removeAll { $0.listing.id == id }; queuedIDs.remove(id)
        if activeID == id { task?.cancel() }
    }
    func pauseAll(preserveQueue: Bool = false) async {
        await background?.pauseAll(preserveQueue: preserveQueue)
        pending = []; queuedIDs = []
        let running = task
        running?.cancel()
        await running?.value
    }
    func remove(_ id: String) async {
        guard !removing, let account else { return }
        removing = true
        defer { removing = false; launchNext() }
        if let background { await background.pause(book: id) } else { pause(id) }
        if activeID == id { await task?.value }
        do {
            try await store.remove(id, account: account)
            items.removeAll { $0.id == id }; failures[id] = nil; storageError = nil
        } catch { storageError = error }
    }
    func removeAll() async throws {
        guard !removing, let account else { return }
        removing = true
        defer { removing = false; launchNext() }
        await pauseAll()
        try await store.removeAll(account: account)
        guard self.account == account else { return }
        items = []; failures = [:]; storageError = nil
    }
    func removeSeries(_ id: String) async throws {
        guard !removing, let account else { return }
        removing = true
        defer { removing = false; launchNext() }
        await background?.remove(series: id)
        let ids = Set(items.filter { $0.series.id == id }.map(\.id))
            .union(pending.filter { $0.series.id == id }.map { $0.listing.id })
            .union(activeSeriesID == id ? [activeID].compactMap { $0 } : [])
        pending.removeAll { $0.series.id == id }; queuedIDs.subtract(ids)
        if activeSeriesID == id {
            let running = task; running?.cancel(); await running?.value
        }
        do {
            try await store.removeSeries(id, account: account)
            guard self.account == account else { return }
            items.removeAll { $0.series.id == id }
            for bookID in ids { failures[bookID] = nil }
            storageError = nil
        } catch { await reload(); throw error }
    }
}
