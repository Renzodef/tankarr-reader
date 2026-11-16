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

    func testLegacyPageCleanupPreservesCoversAndExplicitDownloads() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("SavedLibrary")
        let account = OfflineAccount(instance: "one", username: "reader")
        let storage = ReaderLocalStorage(root: root)
        let generation = await storage.generation()
        let bytes = Data("image".utf8)
        try await storage.write(bytes, to: .covers, key: "series", account: account, generation: generation)
        let legacyPages = root.appendingPathComponent(account.key).appendingPathComponent("pages")
        let explicitDownload = base.appendingPathComponent("OfflineDownloads").appendingPathComponent(account.key)
        for folder in [legacyPages, explicitDownload] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent("page"))
        }

        storage.removeLegacyPages()
        storage.removeLegacyPages()

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPages.path))
        XCTAssertEqual(try Data(contentsOf: explicitDownload.appendingPathComponent("page")), bytes)
        let cover = await storage.read(.covers, "series", account: account)
        XCTAssertEqual(cover, bytes)
    }
}
