import Foundation
import XCTest
@testable import TankarrReaderCore

final class ReaderPerformanceTests: XCTestCase {
    private actor Counter {
        var active = 0
        var peak = 0
        func enter() { active += 1; peak = max(peak, active) }
        func leave() { active -= 1 }
    }

    func testRequestsRespectConcurrencyLimit() async throws {
        let gate = ReaderRequestGate(limit: 2), counter = Counter()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await gate.acquire()
                    await counter.enter()
                    try await Task.sleep(for: .milliseconds(5))
                    await counter.leave()
                    await gate.release()
                }
            }
            try await group.waitForAll()
        }
        let peak = await counter.peak
        XCTAssertEqual(peak, 2)
    }

    func testCancelledWaiterDoesNotBlockNextRequest() async throws {
        let gate = ReaderRequestGate(limit: 1)
        try await gate.acquire()
        let cancelled = Task { try await gate.acquire() }
        await Task.yield()
        cancelled.cancel()
        do { try await cancelled.value; XCTFail("Cancelled waiter acquired a slot") }
        catch { XCTAssertTrue(error is CancellationError) }
        await gate.release()
        try await gate.acquire()
        await gate.release()
    }

    func testCoverCachePersistsAndSeparatesAccounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = OfflineAccount(instance: "one", username: "reader")
        let b = OfflineAccount(instance: "two", username: "reader")
        let cache = ReaderCoverCache(root: root)
        try await cache.save(Data("cover".utf8), id: "series", account: a)
        let reopened = ReaderCoverCache(root: root)
        let hit = try await reopened.data("series", account: a)
        let miss = try await reopened.data("series", account: b)
        XCTAssertEqual(hit, Data("cover".utf8)); XCTAssertNil(miss)
        try await reopened.remove(account: a)
        let removed = try await reopened.data("series", account: a)
        XCTAssertNil(removed)
    }

    func testCoverCacheBoundsSizeAndExpires() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = OfflineAccount(instance: "one", username: "reader")
        let cache = ReaderCoverCache(root: root, limit: 8)
        try await cache.save(Data(repeating: 1, count: 8), id: "first", account: a)
        try await cache.save(Data(repeating: 2, count: 8), id: "second", account: a)
        let first = try await cache.data("first", account: a)
        let second = try await cache.data("second", account: a)
        XCTAssertNil(first); XCTAssertEqual(second?.count, 8)
        let expired = ReaderCoverCache(root: root, lifetime: 0)
        let stale = try await expired.data("second", account: a)
        XCTAssertNil(stale)
    }
}
