import Foundation
import XCTest
@testable import TankarrReaderCore

final class OfflineBookmarksTests: XCTestCase {
    private var root: URL!
    private let account = OfflineAccount(instance: "bookmarks-server", username: "reader")
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BookmarkTests-\(UUID())")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func store() -> OfflineStore { OfflineStore(root: root, freeBytes: { _ in 10_000_000_000 }) }
    private func bookmark(_ series: String = "series-1", page: Int = 2) -> ReaderBookmark {
        ReaderBookmark(seriesId: series, seriesTitle: "Series", bookId: "book-1", label: "Chapter 1",
            pageIndex: page, updatedAt: "2026-11-01T07:00:00Z")
    }

    func testOfflineEditsCoalesceAndOverlayFreshServerSnapshots() throws {
        var state = OfflineBookmarks(account: account, snapshot: [bookmark(), bookmark("series-2")])
        state.writable = true
        try state.enqueue(seriesID: "series-1", value: bookmark(page: 4))
        try state.enqueue(seriesID: "series-1", value: bookmark(page: 6))
        XCTAssertEqual(state.pending.count, 1)
        state.snapshot = [bookmark(page: 1), bookmark("series-2", page: 3)]
        XCTAssertEqual(state.visible.first { $0.seriesId == "series-1" }?.pageIndex, 6)
        XCTAssertEqual(state.visible.first { $0.seriesId == "series-2" }?.pageIndex, 3)
        try state.enqueue(seriesID: "series-1", value: nil)
        XCTAssertEqual(state.pending.count, 1)
        XCTAssertNil(state.pending.first?.value)
        XCTAssertEqual(state.visible.map(\.seriesId), ["series-2"])
    }

    func testPendingEditAndDeleteSurviveRelaunchAndFailedSync() async throws {
        let disk = store()
        try await disk.setBookmarkWritable(true, account: account)
        try await disk.saveBookmarks([bookmark(), bookmark("series-2")], account: account)
        try await disk.queueBookmark(seriesID: "series-1", value: bookmark(page: 7), account: account)
        try await disk.queueBookmark(seriesID: "series-2", value: nil, account: account)
        // No acknowledgement is written when the remote request fails.
        let reopened = store()
        try await reopened.saveBookmarks([bookmark(), bookmark("series-2")], account: account)
        let state = try await reopened.bookmarkState(account: account)
        XCTAssertTrue(state.writable)
        XCTAssertEqual(state.pending.count, 2)
        XCTAssertEqual(state.visible, [bookmark(page: 7)])
        let other = try await reopened.bookmarkState(account: OfflineAccount(instance: "bookmarks-server", username: "other"))
        XCTAssertTrue(other.pending.isEmpty); XCTAssertTrue(other.visible.isEmpty); XCTAssertFalse(other.writable)
    }

    func testLateAcknowledgementCannotDiscardANewerLocalEdit() throws {
        var state = OfflineBookmarks(account: account); state.writable = true
        try state.enqueue(seriesID: "series-1", value: bookmark())
        let oldID = try XCTUnwrap(state.pending.first?.id)
        try state.enqueue(seriesID: "series-1", value: bookmark(page: 5))
        try state.acknowledge(oldID, confirmed: bookmark())
        XCTAssertEqual(state.pending.count, 1)
        XCTAssertEqual(state.visible, [bookmark(page: 5)])
        let newID = try XCTUnwrap(state.pending.first?.id)
        try state.acknowledge(newID, confirmed: bookmark(page: 5))
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertEqual(state.visible, [bookmark(page: 5)])
        try state.acknowledge(newID, confirmed: bookmark(page: 5))
        XCTAssertEqual(state.visible.count, 1)
        try state.enqueue(seriesID: "series-1", value: nil)
        try state.acknowledge(XCTUnwrap(state.pending.first?.id), confirmed: nil)
        XCTAssertTrue(state.visible.isEmpty); XCTAssertTrue(state.pending.isEmpty)
    }

    func testWrongServerAcknowledgementRetainsIntent() throws {
        var state = OfflineBookmarks(account: account); state.writable = true
        try state.enqueue(seriesID: "series-1", value: bookmark(page: 8))
        let id = try XCTUnwrap(state.pending.first?.id)
        XCTAssertThrowsError(try state.acknowledge(id, confirmed: bookmark(page: 0)))
        XCTAssertThrowsError(try state.acknowledge(id, confirmed: nil))
        XCTAssertEqual(state.pending.count, 1); XCTAssertEqual(state.visible, [bookmark(page: 8)])
    }

    func testMediaRemovalPreservesReadingIntentButExplicitAccountRemovalClearsIt() async throws {
        let disk = store()
        try await disk.setBookmarkWritable(true, account: account)
        try await disk.queueBookmark(seriesID: "series-1", value: bookmark(), account: account)
        let series = DemoCatalog.series[0], listing = try DemoCatalog.books(for: DemoCatalog.series[0].id)[0]
        let book = try DemoCatalog.book(listing.id)
        _ = try await disk.begin(book: book, series: series, listing: listing, account: account)
        try await disk.removeAll(account: account)
        let state = try await disk.bookmarkState(account: account)
        let downloads = try await disk.downloads(account: account)
        XCTAssertTrue(downloads.isEmpty); XCTAssertEqual(state.pending.count, 1)
        try await disk.removeAll(account: account, includingBookmarks: true)
        let cleared = try await store().bookmarkState(account: account)
        XCTAssertTrue(cleared.visible.isEmpty); XCTAssertTrue(cleared.pending.isEmpty); XCTAssertFalse(cleared.writable)
    }

    func testUnknownOrRevokedPermissionCannotQueueButDoesNotLosePendingChanges() async throws {
        let disk = store()
        do {
            try await disk.queueBookmark(seriesID: "series-1", value: bookmark(), account: account)
            XCTFail("An unverified account must not offer offline writes")
        } catch {}
        try await disk.setBookmarkWritable(true, account: account)
        try await disk.queueBookmark(seriesID: "series-1", value: bookmark(), account: account)
        try await disk.setBookmarkWritable(false, account: account)
        do {
            try await disk.queueBookmark(seriesID: "series-1", value: nil, account: account)
            XCTFail("A revoked permission must stop new changes")
        } catch {}
        let state = try await store().bookmarkState(account: account)
        XCTAssertFalse(state.writable); XCTAssertEqual(state.pending.count, 1)
    }

    func testLegacyCacheMigratesOnlyAfterServerVerifiesPermission() async throws {
        let metadata = root.appendingPathComponent(account.key).appendingPathComponent(".metadata")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try JSONEncoder().encode([bookmark()]).write(to: metadata.appendingPathComponent("bookmarks.json"))
        let disk = store()
        let before = try await disk.bookmarkState(account: account)
        XCTAssertEqual(before.visible, [bookmark()]); XCTAssertFalse(before.writable)
        try await disk.setBookmarkWritable(true, account: account)
        let after = try await store().bookmarkState(account: account)
        XCTAssertTrue(after.writable); XCTAssertEqual(after.visible, [bookmark()])
        let mode = try FileManager.default.attributesOfItem(atPath: metadata.appendingPathComponent("bookmarks-sync.json").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testMalformedAndForeignAccountStateAreRejected() throws {
        var state = OfflineBookmarks(account: account); state.writable = true
        XCTAssertThrowsError(try state.enqueue(seriesID: "../bad", value: nil))
        XCTAssertThrowsError(try state.enqueue(seriesID: "series-2", value: bookmark()))
        XCTAssertThrowsError(try state.validate(for: OfflineAccount(instance: "other", username: "reader")))
        state.snapshot = [bookmark(), bookmark()]
        XCTAssertThrowsError(try state.validate(for: account))
    }
}
