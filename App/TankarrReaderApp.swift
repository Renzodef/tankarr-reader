import SwiftUI
import Security
import UIKit

@main
struct TankarrReaderApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(model).tint(.orange)
                .task { await model.restore() }
        }
    }
}

enum PasswordStore {
    private static let service = "app.tankarr.reader.account"
    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "reader",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ password: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "reader"]
        let attributes: [String: Any] = [kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            result = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
    }
    static func remove() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "reader"] as CFDictionary)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profile = ServerProfile()
    @Published var api: ReaderAPI?
    @Published var library: [LibrarySeries] = []
    @Published var busy = false
    @Published var error: String?
    @Published var showConnection = false
    @Published var endpointLabel = "Non connesso"
    @Published var isDemo = false
    @Published var bookmarks: [ReaderBookmark] = []
    @Published var bookmarksLoading = false
    @Published var bookmarkBusy = false
    @Published var bookmarkError: String?
    @Published var readingStateWritable = false
    var canBrowse: Bool { api != nil || isDemo }
    var canUseBookmarks: Bool { isDemo || readingStateWritable }
    private var restored = false
    private var sessionID = UUID()
    private let covers = NSCache<NSString, UIImage>()
    private let progress = ReadingProgress()
    private let readingPreferences = ReadingPreferences()
    private let demoBookmarks = DemoBookmarkStore()

    init() {
        covers.totalCostLimit = 32 * 1024 * 1024
        covers.countLimit = 100
        if let data = UserDefaults.standard.data(forKey: "serverProfile"),
           let saved = try? JSONDecoder().decode(ServerProfile.self, from: data) { profile = saved }
    }
    func restore() async {
        guard !restored else { return }; restored = true
        if UserDefaults.standard.bool(forKey: "demoMode") || ProcessInfo.processInfo.arguments.contains("--demo") {
            startDemo(); return
        }
        if let password = PasswordStore.read() { await connect(profile, password: password) }
        else { showConnection = true }
    }
    func connect(_ newProfile: ServerProfile, password: String) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let (client, status) = try await ReaderAPI.connect(profile: newProfile, password: password)
            let result: LibraryResponse = try await client.get("/v1/library")
            try PasswordStore.save(password)
            var accepted = newProfile; accepted.instanceID = status.instanceId
            let stored = try JSONEncoder().encode(accepted)
            UserDefaults.standard.set(stored, forKey: "serverProfile")
            profile = accepted; api = client; isDemo = false; library = result.items; covers.removeAllObjects()
            resetBookmarkSession(); readingStateWritable = status.readingStateWritable == true
            UserDefaults.standard.removeObject(forKey: "demoMode")
            endpointLabel = client.base.host ?? "Connesso"
            showConnection = false
            await refreshBookmarks()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        if isDemo { startDemo(); return }
        guard let password = PasswordStore.read() else { showConnection = true; return }
        await connect(profile, password: password) // Re-evaluate LAN/HTTPS availability on refresh.
    }
    func disconnect() {
        PasswordStore.remove(); UserDefaults.standard.removeObject(forKey: "serverProfile")
        UserDefaults.standard.removeObject(forKey: "demoMode")
        api = nil; isDemo = false; library = []; covers.removeAllObjects(); profile = ServerProfile()
        resetBookmarkSession(); readingStateWritable = false
        endpointLabel = "Non connesso"; error = nil; showConnection = true
    }
    func cover(_ id: String) async -> UIImage? {
        if let cached = covers.object(forKey: id as NSString) { return cached }
        if isDemo, let series = DemoCatalog.series.first(where: { $0.id == id }) {
            let image = DemoArtwork.cover(series)
            covers.setObject(image, forKey: id as NSString, cost: 600 * 900 * 4)
            return image
        }
        guard let api, (try? Endpoint.identifier(id)) != nil,
              let data = try? await api.data("/v1/series/\(id)/cover", timeout: 20),
              let source = UIImage(data: data) else { return nil }
        // Keep thumbnails, not full-size cover bitmaps, in the bounded memory cache.
        let image = await source.byPreparingThumbnail(ofSize: CGSize(width: 360, height: 540)) ?? source
        covers.setObject(image, forKey: id as NSString, cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count)
        return image
    }
    func position(_ book: String) -> Int {
        progress.position(book: book, instance: progressInstance)
    }
    func savePosition(_ page: Int, book: String) {
        progress.save(page, book: book, instance: progressInstance)
    }
    func resumePosition(_ book: ReaderBook, openingPage: Int? = nil) -> Int {
        progress.resumePosition(book: book, instance: progressInstance, openingPage: openingPage, bookmark: bookmark(for: book))
    }
    func readingOptions(_ book: ReaderBook) -> ReadingOptions {
        readingPreferences.options(book: book.id, instance: progressInstance)
    }
    func saveReadingOptions(_ options: ReadingOptions, book: ReaderBook) {
        readingPreferences.save(options, book: book.id, instance: progressInstance)
    }
    private var progressInstance: String { isDemo ? DemoCatalog.instanceID : profile.instanceID ?? "local" }
    func clearProgress() {
        progress.clear(); readingPreferences.clear(); demoBookmarks.clear()
        if isDemo { bookmarks = [] }
    }
    func startDemo() {
        guard !busy else { return }
        api = nil; isDemo = true; library = DemoCatalog.series; covers.removeAllObjects()
        resetBookmarkSession(); readingStateWritable = false; bookmarks = demoBookmarks.all()
        error = nil; endpointLabel = "Demo sul dispositivo"; showConnection = false
        UserDefaults.standard.set(true, forKey: "demoMode")
    }
    private func resetBookmarkSession() {
        sessionID = UUID(); bookmarks = []; bookmarkError = nil; bookmarksLoading = false
    }
    func bookmark(for book: ReaderBook) -> ReaderBookmark? { bookmarks.first { $0.bookId == book.id } }
    func refreshBookmarks() async {
        guard canUseBookmarks, !bookmarkBusy, !bookmarksLoading else { return }
        if isDemo { bookmarks = demoBookmarks.all(); bookmarkError = nil; return }
        guard let client = api else { return }
        let session = sessionID
        bookmarksLoading = true
        defer { if sessionID == session { bookmarksLoading = false } }
        do {
            let result: BookmarksResponse = try await client.get("/v1/bookmarks")
            guard sessionID == session else { return }
            bookmarks = result.items; bookmarkError = nil
        } catch {
            if sessionID == session, !Task.isCancelled { bookmarkError = "Impossibile aggiornare i segnalibri. \(error.localizedDescription)" }
        }
    }
    func saveBookmark(_ book: ReaderBook, page: Int) async {
        guard canUseBookmarks, !bookmarkBusy, !bookmarksLoading, let series = book.seriesId,
              (0..<book.pageCount).contains(page) else { return }
        let session = sessionID
        let client = api
        let demo = isDemo
        bookmarkBusy = true; bookmarkError = nil
        defer { bookmarkBusy = false }
        do {
            let saved: ReaderBookmark
            if demo {
                saved = ReaderBookmark(seriesId: series, seriesTitle: book.seriesTitle, bookId: book.id,
                    label: book.title, pageIndex: page, updatedAt: ISO8601DateFormatter().string(from: Date()))
                demoBookmarks.save(saved)
            } else {
                guard let client else { throw ReaderError.unavailable(0) }
                let result = try await client.saveBookmark(series: series, book: book.id, page: page)
                saved = ReaderBookmark(seriesId: result.seriesId,
                    seriesTitle: result.seriesTitle.isEmpty ? book.seriesTitle : result.seriesTitle,
                    bookId: result.bookId, label: result.label.isEmpty ? book.title : result.label,
                    pageIndex: result.pageIndex, updatedAt: result.updatedAt)
            }
            guard sessionID == session else { return }
            bookmarks.removeAll { $0.seriesId == saved.seriesId }; bookmarks.insert(saved, at: 0)
        } catch {
            if sessionID == session { bookmarkError = "Segnalibro non confermato. Aggiorna l’elenco per verificarlo. \(error.localizedDescription)" }
        }
    }
    func removeBookmark(_ bookmark: ReaderBookmark) async {
        guard canUseBookmarks, !bookmarkBusy, !bookmarksLoading else { return }
        let session = sessionID
        let client = api
        let demo = isDemo
        bookmarkBusy = true; bookmarkError = nil
        defer { bookmarkBusy = false }
        do {
            if demo { demoBookmarks.remove(series: bookmark.seriesId) }
            else {
                guard let client else { throw ReaderError.unavailable(0) }
                try await client.removeBookmark(series: bookmark.seriesId)
            }
            guard sessionID == session else { return }
            bookmarks.removeAll { $0.seriesId == bookmark.seriesId }
        } catch {
            if sessionID == session { bookmarkError = "Rimozione non confermata. Aggiorna l’elenco per verificarla. \(error.localizedDescription)" }
        }
    }
    func books(for series: String) async throws -> [LibraryBook] {
        if isDemo { return try DemoCatalog.books(for: series) }
        guard let api else { throw ReaderError.unavailable(0) }
        let result: BooksResponse = try await api.get("/v1/series/\(try Endpoint.identifier(series))")
        return result.books
    }
    func book(_ id: String) async throws -> ReaderBook {
        if isDemo { return try DemoCatalog.book(id) }
        guard let api else { throw ReaderError.unavailable(0) }
        return try await api.get("/v1/books/\(try Endpoint.identifier(id))")
    }
    func page(_ id: String, at index: Int) async throws -> UIImage {
        if isDemo { return DemoArtwork.page(try DemoCatalog.page(id, at: index)) }
        guard let api else { throw ReaderError.unavailable(0) }
        let data = try await api.data("/v1/books/\(try Endpoint.identifier(id))/pages/\(index)")
        guard let image = UIImage(data: data) else { throw ReaderError.unavailable(415) }
        return image
    }
}
