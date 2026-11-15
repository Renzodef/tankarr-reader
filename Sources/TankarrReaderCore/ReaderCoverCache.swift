import Foundation
import CryptoKit

/// Disposable, bounded cache. Keys include the server identity and account;
/// it contains neither credentials nor URLs and lives outside offline downloads.
public actor ReaderCoverCache {
    private struct Entry { let url: URL; let date: Date; let bytes: Int }
    private let root: URL
    private let limit: Int
    private let lifetime: TimeInterval
    private var entries: [String: Entry]?

    public init(root: URL, limit: Int = 64 * 1024 * 1024, lifetime: TimeInterval = 300) {
        self.root = root; self.limit = limit; self.lifetime = lifetime
    }
    private func key(_ id: String, account: OfflineAccount) -> String {
        account.key + "-" + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func prepare() throws {
        guard entries == nil else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var loaded: [String: Entry] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]) {
            let value = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            guard value.isRegularFile == true else { continue }
            loaded[url.lastPathComponent] = Entry(url: url, date: value.contentModificationDate ?? .distantPast,
                                                  bytes: value.fileSize ?? 0)
        }
        entries = loaded
        trim()
    }
    private func trim() {
        var bytes = entries!.values.reduce(0) { $0 + $1.bytes }
        for (key, entry) in entries!.sorted(by: { $0.value.date < $1.value.date }) {
            guard bytes > limit || Date().timeIntervalSince(entry.date) >= lifetime else { continue }
            try? FileManager.default.removeItem(at: entry.url)
            entries!.removeValue(forKey: key); bytes -= entry.bytes
        }
    }
    public func data(_ id: String, account: OfflineAccount) throws -> Data? {
        try prepare()
        guard let entry = entries![key(id, account: account)], Date().timeIntervalSince(entry.date) < lifetime else { return nil }
        return try? Data(contentsOf: entry.url)
    }
    public func save(_ data: Data, id: String, account: OfflineAccount) throws {
        try prepare()
        guard data.count <= limit else { return }
        let key = key(id, account: account), url = root.appendingPathComponent(key)
        try data.write(to: url, options: .atomic)
        entries![key] = Entry(url: url, date: Date(), bytes: data.count)
        trim()
    }
    public func remove(account: OfflineAccount) throws {
        try prepare()
        for (key, entry) in entries! where key.hasPrefix(account.key + "-") {
            try FileManager.default.removeItem(at: entry.url)
            entries!.removeValue(forKey: key)
        }
    }
}
