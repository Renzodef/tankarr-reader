import Foundation
import CryptoKit

public enum ReaderStorageSection: String, CaseIterable, Sendable {
    case catalogue, covers
}

/// Persistent copies of the catalogue and covers, scoped to each account.
public actor ReaderLocalStorage {
    private let root: URL
    private let fm = FileManager.default
    private var epoch = UUID()

    public init(root: URL) { self.root = root }

    private func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func folder(_ section: ReaderStorageSection, _ account: OfflineAccount) -> URL {
        root.appendingPathComponent(account.key, isDirectory: true)
            .appendingPathComponent(section.rawValue, isDirectory: true)
    }
    private func location(_ section: ReaderStorageSection, _ key: String, _ account: OfflineAccount) -> URL {
        folder(section, account).appendingPathComponent(hash(key))
    }

    /// Old builds kept automatically saved pages here, separately from explicit downloads.
    public nonisolated func removeLegacyPages() {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let accounts = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) else { return }
        for account in accounts {
            guard account.lastPathComponent.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil,
                  let values = try? account.resourceValues(forKeys: keys),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            try? fm.removeItem(at: account.appendingPathComponent("pages", isDirectory: true))
        }
    }

    public func generation() -> UUID { epoch }

    public func read(_ section: ReaderStorageSection, _ key: String, account: OfflineAccount,
                     revision: String? = nil) -> Data? {
        let url = location(section, key, account)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 32 else { return nil }
        if let revision, !data.prefix(32).elementsEqual(SHA256.hash(data: Data(revision.utf8))) { return nil }
        return Data(data.dropFirst(32))
    }

    public func contains(_ section: ReaderStorageSection, _ key: String, account: OfflineAccount,
                         revision: String? = nil) -> Bool {
        let url = location(section, key, account)
        guard let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 33), header.count == 33 else { return false }
        guard let revision else { return true }
        return header.prefix(32).elementsEqual(SHA256.hash(data: Data(revision.utf8)))
    }

    public func write(_ data: Data, to section: ReaderStorageSection, key: String, account: OfflineAccount,
                      generation: UUID, revision: String? = nil) throws {
        guard epoch == generation, !Task.isCancelled else { throw CancellationError() }
        guard !data.isEmpty, data.count <= OfflineStore.maxPageBytes else { throw OfflineError.invalidPage }
        let url = location(section, key, account)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        var privateRoot = root
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try privateRoot.setResourceValues(attributes)
        guard try OfflineStore.availableBytes(at: root) >= OfflineStore.minimumFreeBytes + 2 * Int64(data.count)
        else { throw OfflineError.lowSpace }
        var record = Data(SHA256.hash(data: Data((revision ?? "").utf8)))
        record.append(data)
        try record.write(to: url, options: .atomic)
    }

    public func clear(_ section: ReaderStorageSection? = nil, account: OfflineAccount) throws {
        epoch = UUID()
        let target = section.map { folder($0, account) } ?? root.appendingPathComponent(account.key)
        try removeIfPresent(target)
    }

    private func removeIfPresent(_ url: URL) throws {
        do { try fm.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { }
    }

    public func sizes(account: OfflineAccount) -> [ReaderStorageSection: Int64] {
        var result: [ReaderStorageSection: Int64] = [:]
        let properties: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        for section in ReaderStorageSection.allCases {
            let files = fm.enumerator(at: folder(section, account), includingPropertiesForKeys: Array(properties))
            var total: Int64 = 0
            while let url = files?.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: properties)
                if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
            }
            result[section] = total
        }
        return result
    }
}
