import SwiftUI
import Security
import UIKit

@main
struct TankarrReaderApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(model).environmentObject(model.downloads).tint(.orange)
                .environment(\.locale, model.languageLocale)
                .task { await model.restore() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refreshSystemLanguage() }
                }
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
    @Published private var connectionError: Error?
    @Published var showConnection = false
    @Published private var endpointHost: String?
    @Published var isDemo = false
    @Published private(set) var appLanguage = AppLanguage.system
    @Published var bookmarks: [ReaderBookmark] = []
    @Published var bookmarksLoading = false
    @Published var bookmarkBusy = false
    @Published private var bookmarkFailure: (format: String, error: Error)?
    @Published var readingStateWritable = false
    @Published private(set) var offlineMode = false
    let downloads = DownloadManager()
    var canBrowse: Bool { api != nil || isDemo || offlineMode }
    var canUseBookmarks: Bool { !offlineMode && (isDemo || readingStateWritable) }
    var canViewBookmarks: Bool { offlineMode || canUseBookmarks }
    var visibleLibrary: [LibrarySeries] { offlineMode ? downloadedSeries : library }
    var visibleBookmarks: [ReaderBookmark] {
        offlineMode ? OfflineLibrary.bookmarks(bookmarks, downloads: downloads.items) : bookmarks
    }
    var canDownload: Bool { !offlineMode && (api != nil || isDemo) }
    var error: String? { connectionError.map { $0.localizedDescription } }
    var bookmarkError: String? { bookmarkFailure.map { L10n.format($0.format, $0.error.localizedDescription) } }
    var endpointLabel: String {
        if offlineMode { return L10n.text("Lettura offline") }
        if isDemo { return L10n.text("Demo sul dispositivo") }
        return canBrowse ? endpointHost ?? L10n.text("Connesso") : L10n.text("Non connesso")
    }
    var languageLocale: Locale { Locale(identifier: appLanguage.code()) }
    private var restored = false
    private var sessionID = UUID()
    private let covers = NSCache<NSString, UIImage>()
    private let progress = ReadingProgress()
    private let readingPreferences = ReadingPreferences()
    private let languagePreferences = AppLanguagePreferences()
    private let demoBookmarks = DemoBookmarkStore()

    init() {
        appLanguage = languagePreferences.language
        L10n.language = appLanguage
        covers.totalCostLimit = 32 * 1024 * 1024
        covers.countLimit = 100
        if let data = UserDefaults.standard.data(forKey: "serverProfile"),
           let saved = try? JSONDecoder().decode(ServerProfile.self, from: data) { profile = saved }
    }
    func setLanguage(_ language: AppLanguage) {
        guard appLanguage != language else { return }
        L10n.language = language
        languagePreferences.language = language
        appLanguage = language
    }
    func refreshSystemLanguage() {
        if appLanguage == .system { objectWillChange.send() }
    }
    func restore() async {
        guard !restored else { return }; restored = true
        if UserDefaults.standard.bool(forKey: "demoMode") || ProcessInfo.processInfo.arguments.contains("--demo") {
            let resumeOffline = UserDefaults.standard.bool(forKey: "offlineReading")
                && !ProcessInfo.processInfo.arguments.contains("--demo")
            await startDemo()
            if resumeOffline { await useOffline() }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--offline-demo") { await useOffline() }
            #endif
            return
        }
        await downloads.activate(offlineAccount(profile))
        await restoreCachedBookmarks()
        if !downloads.items.isEmpty { offlineMode = true; library = downloadedSeries }
        if UserDefaults.standard.bool(forKey: "offlineReading"), downloads.account != nil {
            await useOffline(); return
        }
        if let password = PasswordStore.read() { await connect(profile, password: password) }
        else { showConnection = true }
    }
    func connect(_ newProfile: ServerProfile, password: String) async {
        guard !busy else { return }; busy = true; connectionError = nil
        defer { busy = false }
        do {
            let (client, status) = try await ReaderAPI.connect(profile: newProfile, password: password)
            let result: LibraryResponse = try await client.get("/v1/library")
            try PasswordStore.save(password)
            var accepted = newProfile; accepted.instanceID = status.instanceId
            let stored = try JSONEncoder().encode(accepted)
            UserDefaults.standard.set(stored, forKey: "serverProfile")
            await downloads.activate(offlineAccount(accepted))
            profile = accepted; api = client; isDemo = false; offlineMode = false; library = result.items; covers.removeAllObjects()
            resetBookmarkSession(); readingStateWritable = status.readingStateWritable == true
            await restoreCachedBookmarks()
            UserDefaults.standard.removeObject(forKey: "demoMode")
            UserDefaults.standard.removeObject(forKey: "offlineReading")
            endpointHost = client.base.host
            showConnection = false
            await refreshBookmarks()
        } catch {
            connectionError = error
            if api == nil, !downloads.items.isEmpty {
                offlineMode = true; library = downloadedSeries; showConnection = false
            }
        }
    }
    func refresh() async {
        // Pull-to-refresh while offline must not silently reconnect.
        if offlineMode { await downloads.reload(); await restoreCachedBookmarks(); return }
        await reconnect()
    }
    func reconnect() async {
        if isDemo { await startDemo(); return }
        guard let password = PasswordStore.read() else { showConnection = true; return }
        await connect(profile, password: password) // Re-evaluate LAN/HTTPS availability on refresh.
    }
    func disconnect() async {
        do {
            try await downloads.removeAll()
            if let saved = offlineAccount(profile), saved != downloads.account {
                try await downloads.store.removeAll(account: saved)
            }
        }
        catch { connectionError = error; return }
        await downloads.activate(nil)
        PasswordStore.remove(); UserDefaults.standard.removeObject(forKey: "serverProfile")
        UserDefaults.standard.removeObject(forKey: "demoMode")
        UserDefaults.standard.removeObject(forKey: "offlineReading")
        api = nil; isDemo = false; offlineMode = false; library = []; covers.removeAllObjects(); profile = ServerProfile()
        resetBookmarkSession(); readingStateWritable = false
        endpointHost = nil; connectionError = nil; showConnection = true
    }
    private func offlineAccount(_ profile: ServerProfile) -> OfflineAccount? {
        guard let instance = profile.instanceID, !profile.username.isEmpty else { return nil }
        return OfflineAccount(instance: instance, username: profile.username)
    }
    private var downloadedSeries: [LibrarySeries] {
        OfflineLibrary.series(downloads.items)
    }
    func useOffline() async {
        if !offlineMode { await cacheBookmarks() }
        await downloads.pauseAll()
        api = nil; offlineMode = true; library = downloadedSeries; covers.removeAllObjects()
        sessionID = UUID(); bookmarksLoading = false
        readingStateWritable = false; connectionError = nil; showConnection = false
        await restoreCachedBookmarks()
        UserDefaults.standard.set(true, forKey: "offlineReading")
    }
    func cover(_ id: String) async -> UIImage? {
        if let cached = covers.object(forKey: id as NSString) { return cached }
        if offlineMode {
            guard let account = downloads.account,
                  let data = try? await downloads.store.cover(seriesID: id, account: account) else { return nil }
            return UIImage(data: data)
        }
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
        if isDemo { bookmarks = []; Task { await cacheBookmarks() } }
    }
    func startDemo() async {
        guard !busy else { return }
        await downloads.activate(OfflineAccount(instance: DemoCatalog.instanceID, username: "demo"))
        api = nil; isDemo = true; offlineMode = false; library = DemoCatalog.series; covers.removeAllObjects()
        resetBookmarkSession(); readingStateWritable = false; bookmarks = demoBookmarks.all()
        await cacheBookmarks()
        connectionError = nil; endpointHost = nil; showConnection = false
        UserDefaults.standard.set(true, forKey: "demoMode")
        UserDefaults.standard.removeObject(forKey: "offlineReading")
    }
    private func resetBookmarkSession() {
        sessionID = UUID(); bookmarks = []; bookmarkFailure = nil; bookmarksLoading = false
    }
    func bookmark(for book: ReaderBook) -> ReaderBookmark? { bookmarks.first { $0.bookId == book.id } }
    func series(_ id: String) -> LibrarySeries? {
        library.first { $0.id == id } ?? downloads.items.first { $0.series.id == id }?.series
    }
    private func cacheBookmarks() async {
        guard let account = downloads.account else { return }
        let session = sessionID
        do { try await downloads.store.saveBookmarks(bookmarks, account: account) }
        catch {
            if sessionID == session && downloads.account == account {
                bookmarkFailure = ("Impossibile salvare i segnalibri per l’uso offline. %@", error)
            }
        }
    }
    private func restoreCachedBookmarks() async {
        guard let account = downloads.account else { return }
        let session = sessionID
        do {
            let saved = try await downloads.store.bookmarks(account: account)
            guard downloads.account == account, sessionID == session else { return }
            bookmarks = saved
        } catch { bookmarkFailure = ("Impossibile leggere i segnalibri offline. %@", error) }
    }
    func refreshBookmarks() async {
        guard canUseBookmarks, !bookmarkBusy, !bookmarksLoading else { return }
        if isDemo { bookmarks = demoBookmarks.all(); bookmarkFailure = nil; await cacheBookmarks(); return }
        guard let client = api else { return }
        let session = sessionID
        bookmarksLoading = true
        defer { if sessionID == session { bookmarksLoading = false } }
        do {
            let result: BookmarksResponse = try await client.get("/v1/bookmarks")
            guard sessionID == session else { return }
            bookmarks = result.items; bookmarkFailure = nil
            await cacheBookmarks()
        } catch {
            if sessionID == session, !Task.isCancelled { bookmarkFailure = ("Impossibile aggiornare i segnalibri. %@", error) }
        }
    }
    func saveBookmark(_ book: ReaderBook, page: Int) async {
        guard canUseBookmarks, !bookmarkBusy, !bookmarksLoading, let series = book.seriesId,
              (0..<book.pageCount).contains(page) else { return }
        let session = sessionID
        let client = api
        let demo = isDemo
        bookmarkBusy = true; bookmarkFailure = nil
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
            await cacheBookmarks()
        } catch {
            if sessionID == session { bookmarkFailure = ("Segnalibro non confermato. Aggiorna l’elenco per verificarlo. %@", error) }
        }
    }
    func removeBookmark(_ bookmark: ReaderBookmark) async {
        guard canUseBookmarks, !bookmarkBusy, !bookmarksLoading else { return }
        let session = sessionID
        let client = api
        let demo = isDemo
        bookmarkBusy = true; bookmarkFailure = nil
        defer { bookmarkBusy = false }
        do {
            if demo { demoBookmarks.remove(series: bookmark.seriesId) }
            else {
                guard let client else { throw ReaderError.unavailable(0) }
                try await client.removeBookmark(series: bookmark.seriesId)
            }
            guard sessionID == session else { return }
            bookmarks.removeAll { $0.seriesId == bookmark.seriesId }
            await cacheBookmarks()
        } catch {
            if sessionID == session { bookmarkFailure = ("Rimozione non confermata. Aggiorna l’elenco per verificarla. %@", error) }
        }
    }
    func books(for series: String) async throws -> [LibraryBook] {
        if offlineMode { return OfflineLibrary.books(seriesID: series, downloads: downloads.items) }
        if isDemo { return try DemoCatalog.books(for: series) }
        guard let api else { throw ReaderError.unavailable(0) }
        let result: BooksResponse = try await api.get("/v1/series/\(try Endpoint.identifier(series))")
        return result.books
    }
    func book(_ id: String) async throws -> ReaderBook {
        if let account = downloads.account, let cached = try await downloads.store.book(id, account: account) { return cached }
        if offlineMode { throw OfflineError.notDownloaded }
        if isDemo { return try DemoCatalog.book(id) }
        guard let api else { throw ReaderError.unavailable(0) }
        return try await api.get("/v1/books/\(try Endpoint.identifier(id))")
    }
    func page(_ id: String, at index: Int) async throws -> UIImage {
        if let account = downloads.account, let data = try await downloads.store.page(id, index: index, account: account) {
            guard let image = UIImage(data: data) else { throw OfflineError.incomplete }
            return image
        }
        if offlineMode { throw OfflineError.notDownloaded }
        if isDemo { return DemoArtwork.page(try DemoCatalog.page(id, at: index)) }
        guard let api else { throw ReaderError.unavailable(0) }
        let data = try await api.data("/v1/books/\(try Endpoint.identifier(id))/pages/\(index)")
        guard let image = UIImage(data: data) else { throw ReaderError.unavailable(415) }
        return image
    }
}
