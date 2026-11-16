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

    func testSavedLibrarySurvivesReopenAndIsolatesAccounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = OfflineAccount(instance: "one", username: "reader")
        let other = OfflineAccount(instance: "two", username: "reader")
        let storage = ReaderLocalStorage(root: root)
        let generation = await storage.generation()
        let cover = Data("cover".utf8)
        try await storage.write(cover, to: .covers, key: "series", account: account,
                                generation: generation, revision: "original")
        let reopened = ReaderLocalStorage(root: root)
        let hit = await reopened.read(.covers, "series", account: account, revision: "original")
        let stale = await reopened.read(.covers, "series", account: account, revision: "updated")
        let otherAccount = await reopened.read(.covers, "series", account: other)
        XCTAssertEqual(hit, cover)
        XCTAssertNil(stale)
        XCTAssertNil(otherAccount)
    }

    func testUpdatedBookReplacesSavedPagesAndDeletionRejectsLateWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = OfflineAccount(instance: "one", username: "reader")
        let storage = ReaderLocalStorage(root: root)
        let generation = await storage.generation()
        let page = Data("page".utf8)
        try await storage.write(page, to: .pages, key: "1", account: account,
                                generation: generation, group: "book", revision: "original")
        try await storage.write(page, to: .pages, key: "2", account: account,
                                generation: generation, group: "book", revision: "updated")
        let removed = await storage.read(.pages, "1", account: account, group: "book")
        XCTAssertNil(removed)
        let sizes = await storage.sizes(account: account)
        XCTAssertGreaterThan(sizes[.pages, default: 0], 0)
        try await storage.clear(.pages, account: account)
        do {
            try await storage.write(page, to: .pages, key: "2", account: account,
                                    generation: generation, group: "book", revision: "updated")
            XCTFail("A late result recreated deleted pages")
        } catch is CancellationError {}
        let afterClear = await storage.sizes(account: account)
        XCTAssertEqual(afterClear[.pages], 0)
    }
}
