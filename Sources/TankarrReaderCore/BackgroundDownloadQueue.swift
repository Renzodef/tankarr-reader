import Foundation

/// Durable intent, without URLs or credentials. URLSession owns network requests.
public struct BackgroundDownloadJob: Codable, Sendable {
    public let token: UUID
    public let series: LibrarySeries
    public let listing: LibraryBook
    /// nil = book metadata is still needed; [] = all pages are saved.
    public var remaining: [Int]?
    public init(series: LibrarySeries, listing: LibraryBook) {
        token = UUID(); self.series = series; self.listing = listing
    }
}

public struct BackgroundPage: Codable, Hashable, Sendable {
    public let account: String
    public let token: UUID
    public let book: String
    public let index: Int?
    public init(account: String, job: BackgroundDownloadJob, index: Int?) {
        self.account = account; token = job.token; book = job.listing.id; self.index = index
    }
    public var taskDescription: String { String(data: try! JSONEncoder().encode(self), encoding: .utf8)! }
    public init?(taskDescription: String?) {
        guard let taskDescription, let data = taskDescription.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              (try? Endpoint.identifier(value.book)) != nil,
              value.index == nil || (0..<20_000).contains(value.index!) else { return nil }
        self = value
    }
}

public struct BackgroundDownloadQueue: Codable, Sendable {
    public let schema: Int
    public let account: String
    public var jobs: [BackgroundDownloadJob]
    public init(account: OfflineAccount) { schema = 1; self.account = account.key; jobs = [] }
    public func accepts(_ page: BackgroundPage) -> Bool {
        guard page.account == account, let job = jobs.first(where: { $0.token == page.token && $0.listing.id == page.book }) else { return false }
        if let index = page.index { return job.remaining?.contains(index) == true }
        return job.remaining == nil
    }
    /// Cancelled transfers may finish after a retry has replaced their task.
    /// Only a failure from the currently owned task may pause the queue.
    public func acceptsFailure(_ page: BackgroundPage, taskID: Int,
                               currentTaskID: Int?, paused: Bool) -> Bool {
        !paused && currentTaskID == taskID && accepts(page)
    }
    public func canResume(paused: Bool) -> Bool { paused && !jobs.isEmpty }
    /// Batch pages instead of waking iOS once per page. Only two connections run
    /// concurrently; the bounded batch limits session/disk overhead on big packs.
    public func next(excluding running: Set<BackgroundPage>, limit: Int = 64) -> [BackgroundPage] {
        var result: [BackgroundPage] = []
        var slots = max(0, limit - running.count)
        for job in jobs {
            guard slots > 0 else { break }
            let indices: [Int?] = job.remaining.map { $0.map(Optional.some) } ?? [nil]
            for index in indices where slots > 0 {
                let page = BackgroundPage(account: account, job: job, index: index)
                if !running.contains(page) { result.append(page); slots -= 1 }
            }
        }
        return result
    }
    public func validate(for account: OfflineAccount) throws {
        guard schema == 1, self.account == account.key, jobs.count <= 20_000,
              Set(jobs.map(\.listing.id)).count == jobs.count,
              Set(jobs.map(\.token)).count == jobs.count else { throw OfflineError.invalidStorage }
        for job in jobs {
            _ = try Endpoint.identifier(job.series.id); _ = try Endpoint.identifier(job.listing.id)
            if let remaining = job.remaining {
                guard remaining.count <= 20_000, Set(remaining).count == remaining.count,
                      remaining.allSatisfy({ (0..<20_000).contains($0) }) else { throw OfflineError.invalidStorage }
            }
        }
    }
}
