import Foundation

/// A tombstone is retained until DELETE succeeds; an old server snapshot must
/// never make a locally removed bookmark reappear during a failed reconnect.
public struct BookmarkChange: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let seriesID: String
    public let value: ReaderBookmark?
    public init(seriesID: String, value: ReaderBookmark?) {
        id = UUID(); self.seriesID = seriesID; self.value = value
    }
}

/// Server snapshot and unsent intent share one atomic file per server/account.
/// The last explicit local action for a series wins when connectivity returns.
public struct OfflineBookmarks: Codable, Sendable {
    public let schema: Int
    public let account: String
    public var writable: Bool
    public var snapshot: [ReaderBookmark]
    public private(set) var pending: [BookmarkChange]
    public init(account: OfflineAccount, snapshot: [ReaderBookmark] = []) {
        schema = 1; self.account = account.key; writable = false
        self.snapshot = snapshot; pending = []
    }
    public var visible: [ReaderBookmark] {
        var values = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.seriesId, $0) })
        for change in pending { values[change.seriesID] = change.value }
        return values.values.sorted {
            $0.updatedAt == $1.updatedAt ? $0.seriesId < $1.seriesId : $0.updatedAt > $1.updatedAt
        }
    }
    public mutating func enqueue(seriesID: String, value: ReaderBookmark?) throws {
        guard writable else { throw ReaderError.unavailable(403) }
        _ = try Endpoint.identifier(seriesID)
        if let value {
            try Self.validate(value)
            guard value.seriesId == seriesID else { throw OfflineError.invalidStorage }
        }
        pending.removeAll { $0.seriesID == seriesID }
        pending.append(BookmarkChange(seriesID: seriesID, value: value))
    }
    public mutating func acknowledge(_ id: UUID, confirmed: ReaderBookmark?) throws {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let change = pending[index]
        if let requested = change.value {
            guard let confirmed, confirmed.seriesId == change.seriesID,
                  confirmed.bookId == requested.bookId, confirmed.pageIndex == requested.pageIndex else {
                throw OfflineError.invalidStorage
            }
            try Self.validate(confirmed)
            snapshot.removeAll { $0.seriesId == change.seriesID }
            snapshot.append(ReaderBookmark(seriesId: confirmed.seriesId,
                seriesTitle: confirmed.seriesTitle.isEmpty ? requested.seriesTitle : confirmed.seriesTitle,
                bookId: confirmed.bookId, label: confirmed.label.isEmpty ? requested.label : confirmed.label,
                pageIndex: confirmed.pageIndex, updatedAt: confirmed.updatedAt))
        } else {
            guard confirmed == nil else { throw OfflineError.invalidStorage }
            snapshot.removeAll { $0.seriesId == change.seriesID }
        }
        pending.remove(at: index)
    }
    public func validate(for account: OfflineAccount) throws {
        guard schema == 1, self.account == account.key, snapshot.count <= 10000, pending.count <= 10000,
              Set(snapshot.map(\.seriesId)).count == snapshot.count,
              Set(pending.map(\.seriesID)).count == pending.count,
              Set(pending.map(\.id)).count == pending.count else { throw OfflineError.invalidStorage }
        for value in snapshot { try Self.validate(value) }
        for change in pending {
            _ = try Endpoint.identifier(change.seriesID)
            if let value = change.value {
                try Self.validate(value)
                guard value.seriesId == change.seriesID else { throw OfflineError.invalidStorage }
            }
        }
    }
    private static func validate(_ value: ReaderBookmark) throws {
        _ = try Endpoint.identifier(value.seriesId); _ = try Endpoint.identifier(value.bookId)
        guard value.pageIndex >= 0 else { throw OfflineError.invalidStorage }
    }
}
