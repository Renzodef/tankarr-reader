import Foundation
import ImageIO
import UIKit

/// One persistent iOS transfer session per account. All mutations (including
/// cancellation and delegate events) are serialized through operations, not just
/// through MainActor: a disk await must not let a late callback undo a removal.
@MainActor
final class BackgroundDownloads {
    static let prefix = "app.tankarr.reader.downloads."
    let account: OfflineAccount
    let store: OfflineStore
    private var api: ReaderAPI
    private var queue: BackgroundDownloadQueue
    private var running: [BackgroundPage: URLSessionDownloadTask] = [:]
    private var tail: Task<Void, Never>?
    private var started = false
    private var paused = false
    private var completion: (() -> Void)?
    private var finishedEvents = false
    private var session: URLSession!
    var changed: (([BackgroundDownloadJob], Bool) -> Void)?
    var saved: ((OfflineDownload) -> Void)?
    var failed: ((String, Error) -> Void)?

    init(account: OfflineAccount, store: OfflineStore, api: ReaderAPI) {
        self.account = account; self.store = store; self.api = api
        queue = BackgroundDownloadQueue(account: account)
        let config = URLSessionConfiguration.background(withIdentifier: Self.prefix + account.key)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 7 * 24 * 3600
        config.httpMaximumConnectionsPerHost = 2
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        let delegate = BackgroundDownloadDelegate(owner: self)
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    @discardableResult
    private func operation(_ body: @escaping () async throws -> Void) -> Task<Void, Never> {
        let previous = tail
        let next = Task {
            await previous?.value
            do { try await restore(); try await body() }
            catch { await stopForError(error, book: queue.jobs.first?.listing.id ?? "") }
        }
        tail = next
        return next
    }
    private func restore() async throws {
        guard !started else { return }
        queue = try await store.backgroundQueue(account: account)
        let tasks = await session.allTasks
        for task in tasks {
            guard let task = task as? URLSessionDownloadTask,
                  let page = BackgroundPage(taskDescription: task.taskDescription), queue.accepts(page),
                  running[page] == nil, task.state != .completed, task.state != .canceling else {
                task.cancel(); continue
            }
            running[page] = task
            if task.state == .suspended { task.resume() }
        }
        started = true
        notify()
    }
    func start(api: ReaderAPI) async {
        await operation {
            if self.api.base != api.base {
                // Foreground reconnect may switch LAN -> HTTPS. Do not leave
                // the durable queue attached to an unreachable old LAN route.
                self.running.values.forEach { $0.cancel() }; self.running = [:]
            }
            self.api = api; self.paused = false
            try await self.pump()
        }.value
    }
    func close() {
        session.invalidateAndCancel()
        let callback = completion; completion = nil; callback?()
    }
    func attachEvents(_ completion: @escaping () -> Void) {
        self.completion = completion
        operation {
            if self.finishedEvents { self.finishEvents() }
        }
    }
    private func notify() { changed?(queue.jobs, queue.canResume(paused: paused)) }
    private func persist() async throws {
        try await store.saveBackgroundQueue(queue, account: account)
        notify()
    }
    func enqueue(series: LibrarySeries, books: [LibraryBook]) {
        operation {
            for book in books where !self.queue.jobs.contains(where: { $0.listing.id == book.id }) {
                if try await self.store.record(book.id, account: self.account)?.complete == true { continue }
                self.queue.jobs.append(BackgroundDownloadJob(series: series, listing: book))
            }
            self.paused = false
            // Persist the entire selection before the first task is submitted.
            try await self.persist()
            try await self.pump()
        }
    }
    /// An explicit pause removes only that intent; saved pages remain resumable.
    func pause(book: String) async {
        await operation { try await self.cancel(where: { $0.listing.id == book }) }.value
    }
    func pauseAll(preserveQueue: Bool = false) async {
        await operation {
            self.paused = true
            if !preserveQueue { self.queue.jobs = []; try await self.persist() }
            self.running.values.forEach { $0.cancel() }; self.running = [:]
            self.notify()
        }.value
    }
    func remove(series: String) async {
        await operation { try await self.cancel(where: { $0.series.id == series }) }.value
    }
    private func cancel(where predicate: (BackgroundDownloadJob) -> Bool) async throws {
        let tokens = Set(queue.jobs.filter(predicate).map(\.token))
        queue.jobs.removeAll(where: predicate)
        // Fence callbacks durably before touching their tasks or local pages.
        try await persist()
        for (page, task) in running where tokens.contains(page.token) { task.cancel(); running[page] = nil }
        try await pump()
    }
    private func stopForError(_ error: Error, book: String) async {
        paused = !queue.jobs.isEmpty
        running.values.forEach { $0.cancel() }; running = [:]
        // Never clear queued chapters on a transport failure or suspension.
        // Their intent stays on disk and start() retries on the next foreground.
        notify()
        if queue.jobs.contains(where: { $0.listing.id == book }) { failed?(book, error) }
    }
    private func pump() async throws {
        guard !paused else { return }
        // Finish any page commits that happened before a process interruption.
        for job in queue.jobs where job.remaining?.isEmpty == true {
            let record = try await store.finish(job.listing.id, generation: job.token, account: account)
            saved?(record); queue.jobs.removeAll { $0.token == job.token }
            try await persist()
        }
        let candidates = queue.next(excluding: Set(running.keys))
        var reconciled = false
        for page in candidates {
            if let index = page.index,
               try await store.hasPage(page.book, index: index, generation: page.token, account: account) {
                if let offset = queue.jobs.firstIndex(where: { $0.token == page.token }) {
                    queue.jobs[offset].remaining?.removeAll { $0 == index }
                    try await persist(); reconciled = true
                }
                continue
            }
            // Reserve headroom before admitting the batch; recheck every commit.
            do { try await store.checkSpace(for: OfflineStore.maxPageBytes * (running.count + 1)) }
            catch { if !running.isEmpty { break }; throw error }
            let request = try api.backgroundRequest(book: page.book, page: page.index)
            let task = session.downloadTask(with: request)
            task.taskDescription = page.taskDescription
            task.countOfBytesClientExpectsToReceive = page.index == nil ? 64 * 1024 : 4 * 1024 * 1024
            running[page] = task; task.resume()
        }
        if reconciled { try await pump() }
        notify()
    }
    fileprivate func received(_ page: BackgroundPage?, taskID: Int, file: URL?, response: URLResponse?, original: URL?, error: Error?) {
        operation {
            defer { if let file { try? FileManager.default.removeItem(at: file) } }
            // On a background relaunch iOS may deliver an already completed
            // task that allTasks no longer lists. Accept that saved page while
            // still rejecting a replaced task or an explicitly paused queue.
            guard let page, !self.paused, self.queue.accepts(page),
                  self.running[page]?.taskIdentifier == taskID || self.running[page] == nil else { return }
            self.running[page] = nil
            do {
                if let error { throw error }
                guard let file, let http = response as? HTTPURLResponse else { throw ReaderError.unavailable(0) }
                if http.statusCode == 401 { throw ReaderError.unauthorized }
                // Background URLSession follows redirects itself; never accept a
                // redirected/error response as book metadata or saved page data.
                guard http.statusCode == 200, http.url == original else { throw ReaderError.unavailable(http.statusCode) }
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= (page.index == nil ? 2 * 1024 * 1024 : OfflineStore.maxPageBytes) else { throw OfflineError.invalidPage }
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                guard let offset = self.queue.jobs.firstIndex(where: { $0.token == page.token }) else { return }
                if let index = page.index {
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          CGImageSourceGetStatus(source) == .statusComplete, CGImageSourceGetCount(source) > 0,
                          CGImageSourceCopyPropertiesAtIndex(source, 0, nil) != nil else { throw OfflineError.invalidPage }
                    let record = try await self.store.savePage(data, id: page.book, index: index, generation: page.token, account: self.account)
                    self.saved?(record)
                    self.queue.jobs[offset].remaining?.removeAll { $0 == index }
                } else {
                    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let book = try decoder.decode(ReaderBook.self, from: data)
                    let job = self.queue.jobs[offset]
                    let record = try await self.store.begin(book: book, series: job.series, listing: job.listing,
                        account: self.account, generation: job.token)
                    self.saved?(record)
                    var missing: [Int] = []
                    for index in 0..<book.pageCount {
                        if try await !self.store.hasPage(book.id, index: index, generation: job.token, account: self.account) { missing.append(index) }
                    }
                    self.queue.jobs[offset].remaining = missing
                }
                try await self.persist()
                try await self.pump()
            } catch { await self.stopForError(error, book: page.book) }
        }
    }
    fileprivate func failedTask(_ page: BackgroundPage?, taskID: Int, error: Error) {
        operation {
            guard let page, self.queue.acceptsFailure(page, taskID: taskID,
                currentTaskID: self.running[page]?.taskIdentifier, paused: self.paused) else { return }
            await self.stopForError(error, book: page.book)
        }
    }
    fileprivate func eventsFinished() {
        // The callback is queued after all page commits, queue writes and new
        // batch submissions. Only then tell iOS it can suspend the app again.
        operation { self.finishedEvents = true; self.finishEvents() }
    }
    private func finishEvents() {
        guard let completion else { return }
        self.completion = nil; finishedEvents = false; completion()
    }
}

private final class BackgroundDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private weak var owner: BackgroundDownloads?
    init(owner: BackgroundDownloads) { self.owner = owner }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let page = BackgroundPage(taskDescription: downloadTask.taskDescription)
        var kept: URL?
        var failure: Error?
        do {
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BackgroundIncoming", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let file = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: file)
            kept = file
            try FileManager.default.setAttributes([.posixPermissions: 0o600,
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        } catch { failure = error }
        // Move synchronously: URLSession deletes its temporary file on return.
        let file = kept, error = failure
        DispatchQueue.main.async { [weak self] in
            guard let owner = self?.owner else { if let file { try? FileManager.default.removeItem(at: file) }; return }
            owner.received(page, taskID: downloadTask.taskIdentifier, file: file, response: downloadTask.response, original: downloadTask.originalRequest?.url, error: error)
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let page = BackgroundPage(taskDescription: task.taskDescription)
        DispatchQueue.main.async { [weak self] in self?.owner?.failedTask(page, taskID: task.taskIdentifier, error: error) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let max = BackgroundPage(taskDescription: downloadTask.taskDescription)?.index == nil ? 2 * 1024 * 1024 : OfflineStore.maxPageBytes
        if totalBytesWritten > max || totalBytesExpectedToWrite > max { downloadTask.cancel() }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in self?.owner?.eventsFinished() }
    }
}
