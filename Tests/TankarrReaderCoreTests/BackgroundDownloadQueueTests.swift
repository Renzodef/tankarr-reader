import Foundation
import XCTest
@testable import TankarrReaderCore

final class BackgroundDownloadQueueTests: XCTestCase {
    private let account = OfflineAccount(instance: "background-fixture", username: "reader")
    private func job(_ number: Int = 0) throws -> BackgroundDownloadJob {
        let series = DemoCatalog.series[number]
        return BackgroundDownloadJob(series: series, listing: try DemoCatalog.books(for: series.id)[0])
    }

    func testWholeSelectionSurvivesProcessLossIncludingUnstartedBooks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var queue = BackgroundDownloadQueue(account: account)
        queue.jobs = try [job(), job(1), job(2)]
        queue.jobs[0].remaining = [1, 2]
        try await OfflineStore(root: root).saveBackgroundQueue(queue, account: account)
        let reopened = try await OfflineStore(root: root).backgroundQueue(account: account)
        XCTAssertEqual(reopened.jobs.map(\.token), queue.jobs.map(\.token))
        XCTAssertEqual(reopened.jobs[0].remaining, [1, 2])
        XCTAssertNil(reopened.jobs[1].remaining, "An unstarted chapter must survive closing the app")
        let raw = try String(contentsOf: root.appendingPathComponent(account.key).appendingPathComponent(".metadata/background-queue.json"))
        XCTAssertFalse(raw.contains("password")); XCTAssertFalse(raw.contains("Authorization")); XCTAssertFalse(raw.contains("https://"))
        let other = try await OfflineStore(root: root).backgroundQueue(account: OfflineAccount(instance: "other", username: "reader"))
        XCTAssertTrue(other.jobs.isEmpty)
    }

    func testBatchContinuesWithoutDuplicatesAndHonorsLimit() throws {
        var queue = BackgroundDownloadQueue(account: account)
        queue.jobs = try [job(), job(1)]
        queue.jobs[0].remaining = Array(0..<150)
        let initial = queue.next(excluding: [])
        XCTAssertEqual(initial.count, 64)
        XCTAssertEqual(initial.compactMap(\.index), Array(0..<64))
        XCTAssertTrue(queue.next(excluding: Set(initial)).isEmpty)
        queue.jobs[0].remaining?.removeFirst(20)
        let active = Set(initial.dropFirst(20))
        let refill = queue.next(excluding: active)
        XCTAssertEqual(refill.compactMap(\.index), Array(64..<84))
        XCTAssertTrue(active.isDisjoint(with: refill))
    }

    func testPauseRemovalAndReplacementFenceLateResponses() throws {
        var queue = BackgroundDownloadQueue(account: account)
        queue.jobs = try [job(), job(1)]
        let old = BackgroundPage(account: account.key, job: queue.jobs[0], index: nil)
        XCTAssertTrue(queue.accepts(old))
        queue.jobs.removeFirst()
        XCTAssertFalse(queue.accepts(old)); XCTAssertEqual(queue.jobs.count, 1)
        queue.jobs.insert(try job(), at: 0)
        XCTAssertFalse(queue.accepts(old), "A restarted book gets a new token")
        let other = BackgroundPage(account: "other", job: queue.jobs[0], index: nil)
        XCTAssertFalse(queue.accepts(other))
    }

    func testDiskCommitBeforeQueueCommitDoesNotLosePageAfterRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineStore(root: root, freeBytes: { _ in 10_000_000_000 })
        var queue = BackgroundDownloadQueue(account: account)
        queue.jobs = try [job()]
        let job = queue.jobs[0], book = try DemoCatalog.book(job.listing.id)
        _ = try await store.begin(book: book, series: job.series, listing: job.listing, account: account, generation: job.token)
        queue.jobs[0].remaining = [0, 1, 2]
        try await store.saveBackgroundQueue(queue, account: account)
        _ = try await store.savePage(Data("page".utf8), id: book.id, index: 0, generation: job.token, account: account)
        // Simulate process loss between the two atomic writes.
        let reopened = OfflineStore(root: root)
        let restored = try await reopened.backgroundQueue(account: account)
        let present = try await reopened.hasPage(book.id, index: 0, generation: restored.jobs[0].token, account: account)
        XCTAssertTrue(present, "Scheduler reconciles this page instead of downloading it again")
    }

    func testQueueValidationAndTaskDescriptionsRejectInvalidData() throws {
        var queue = BackgroundDownloadQueue(account: account)
        queue.jobs = try [job()]
        let page = BackgroundPage(account: account.key, job: queue.jobs[0], index: nil)
        XCTAssertEqual(BackgroundPage(taskDescription: page.taskDescription), page)
        XCTAssertNil(BackgroundPage(taskDescription: "not json"))
        queue.jobs[0].remaining = [-1]
        XCTAssertThrowsError(try queue.validate(for: account))
        queue.jobs[0].remaining = [0, 0]
        XCTAssertThrowsError(try queue.validate(for: account))
        queue.jobs[0].remaining = []
        XCTAssertFalse(queue.accepts(page), "A metadata response cannot overwrite a prepared book")
    }

    func testBackgroundRequestsUseSameEndpointAndNeverPutPasswordInURL() throws {
        let api = ReaderAPI(base: URL(string: "https://example.org/reader")!, username: "reader", password: "test-only")
        let metadata = try api.backgroundRequest(book: "chapter-1", page: nil)
        let page = try api.backgroundRequest(book: "chapter-1", page: 2)
        XCTAssertEqual(metadata.url?.path, "/reader/v1/books/chapter-1")
        XCTAssertEqual(page.url?.path, "/reader/v1/books/chapter-1/pages/2")
        XCTAssertEqual(page.httpMethod, "GET")
        XCTAssertFalse(page.httpShouldHandleCookies)
        XCTAssertNil(page.url?.user); XCTAssertNil(page.url?.password); XCTAssertNil(page.url?.query)
        XCTAssertNotNil(page.value(forHTTPHeaderField: "Authorization"))
        XCTAssertThrowsError(try api.backgroundRequest(book: "../other", page: 0))
        XCTAssertThrowsError(try api.backgroundRequest(book: "chapter-1", page: -1))
    }
}
