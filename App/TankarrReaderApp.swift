import SwiftUI
import Security
import UIKit
import Network

@main
struct TankarrReaderApp: App {
    @UIApplicationDelegateAdaptor(ReaderAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(model).environmentObject(model.downloads).tint(.orange)
                .environment(\.locale, model.languageLocale)
                .task { await model.restore() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.becameActive() }
                    }
                }
        }
    }
}

@MainActor
final class ReaderAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ReaderPush.shared.installDelegate()
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await ReaderPush.shared.receiveToken(deviceToken) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        ReaderPush.shared.notice = L10n.text("Registrazione notifiche in attesa. Riprova tornando online.")
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            await AppModel.shared.restoreBackgroundDownloads(identifier: identifier, completion: completionHandler)
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
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
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
    static let shared = AppModel()
    @Published var profile = ServerProfile()
    @Published var api: ReaderAPI?
    @Published var library: [LibrarySeries] = []
    @Published var busy = false
    @Published var refreshing = false
    @Published var refreshNotice: String?
    @Published private var connectionError: Error?
    @Published var showConnection = false
    @Published private var endpointHost: String?
    @Published var isDemo = false
    @Published private(set) var appLanguage = AppLanguage.english
    @Published var bookmarks: [ReaderBookmark] = []
    @Published var bookmarksLoading = false
    @Published var bookmarkBusy = false
    @Published private(set) var pendingBookmarkSeries: Set<String> = []
    @Published private var offlineBookmarkWritable = false
    @Published private var bookmarkFailure: (format: String, error: Error)?
    @Published var readingStateWritable = false
    @Published var followingWritable = false
    @Published var pushNotificationsAvailable = false
    @Published var followedSeries: Set<String> = []
    @Published var followingBusy: Set<String> = []
    @Published var followingError: String?
    @Published var pendingPushSeriesID: String?
    @Published private(set) var offlineMode = false
    @Published private(set) var automaticOffline = false
    let downloads = DownloadManager()
    var canBrowse: Bool { api != nil || isDemo || offlineMode }
    var canUseBookmarks: Bool { isDemo || (offlineMode ? offlineBookmarkWritable : readingStateWritable) }
    var canViewBookmarks: Bool { offlineMode || canUseBookmarks || !pendingBookmarkSeries.isEmpty }
    var visibleLibrary: [LibrarySeries] { offlineMode ? downloadedSeries : library }
    var visibleBookmarks: [ReaderBookmark] {
        offlineMode ? OfflineLibrary.bookmarks(bookmarks, downloads: downloads.items) : bookmarks
    }
    var canDownload: Bool { !offlineMode && (api != nil || isDemo) }
    var error: String? { connectionError.map { $0.localizedDescription } }
    var bookmarkError: String? { bookmarkFailure.map { L10n.format($0.format, $0.error.localizedDescription) } }
    var endpointLabel: String {
        if offlineMode { return L10n.text(automaticOffline ? "Offline automatico" : "Lettura offline") }
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
    private let networkMonitor = NWPathMonitor()
    private var networkAvailable: Bool?
    private var switchingOffline = false

    init() {
        appLanguage = languagePreferences.language
        L10n.language = appLanguage
        covers.totalCostLimit = 32 * 1024 * 1024
        covers.countLimit = 100
        if let data = UserDefaults.standard.data(forKey: "serverProfile"),
           let saved = try? JSONDecoder().decode(ServerProfile.self, from: data) { profile = saved }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status != .unsatisfied
            Task { @MainActor [weak self] in await self?.networkChanged(available: available) }
        }
        networkMonitor.start(queue: DispatchQueue(label: "reader-connectivity"))
    }
    private func networkChanged(available: Bool) async {
        let changed = networkAvailable != available
        networkAvailable = available
        guard changed, restored, !isDemo, !busy else { return }
        if available {
            if automaticOffline { await reconnect() }
        } else if api != nil && !offlineMode && downloads.items.contains(where: \.complete) {
            await useOffline(automatic: true)
        }
    }
    func becameActive() async {
        if automaticOffline, networkAvailable != false { await reconnect() }
        await resumeBackgroundDownloads()
        await refreshBookmarks()
        await refreshFollows()
        await ReaderPush.shared.synchronize()
    }
    private func fallBackOffline(_ error: Error, client: ReaderAPI? = nil) async {
        guard !Task.isCancelled, !busy, !isDemo, !offlineMode,
              client == nil || client === api,
              OfflineConnectivity.isReachabilityFailure(error),
              downloads.items.contains(where: \.complete) else { return }
        await useOffline(automatic: true)
    }
    func setLanguage(_ language: AppLanguage) {
        guard appLanguage != language else { return }
        L10n.language = language
        languagePreferences.language = language
        appLanguage = language
    }
    func restore() async {
        guard !restored else { return }; restored = true
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--background-download-test"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
            let address = ProcessInfo.processInfo.arguments[index + 1]
            if let url = try? Endpoint.validate(address), url.host == "127.0.0.1" {
                await connect(ServerProfile(localAddress: address, username: "test-reader", mode: .local), password: "test-only")
                return
            }
        }
        #endif
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
        restoreFollows()
        if !downloads.items.isEmpty { offlineMode = true; library = downloadedSeries }
        if UserDefaults.standard.bool(forKey: "offlineReading"), downloads.account != nil {
            await useOffline(); return
        }
        if let password = PasswordStore.read() {
            // Upgrade the existing keychain item's accessibility on an unlocked
            // foreground launch, so page batches can continue with a locked screen.
            try? PasswordStore.save(password)
            await restoreBackgroundDownloads()
            await connect(profile, password: password)
        }
        else { showConnection = true }
    }
    func restoreBackgroundDownloads(identifier: String? = nil, completion: (() -> Void)? = nil) async {
        guard !UserDefaults.standard.bool(forKey: "offlineReading"),
              let account = offlineAccount(profile),
              identifier == nil || identifier == BackgroundDownloads.prefix + account.key,
              let baseText = UserDefaults.standard.string(forKey: "downloadEndpoint"),
              let base = try? Endpoint.validate(baseText), (try? profile.candidates().contains(base)) == true,
              let password = PasswordStore.read() else { completion?(); return }
        await downloads.activate(account)
        await downloads.configureBackground(api: ReaderAPI(base: base, username: profile.username, password: password), completion: completion)
    }
    func resumeBackgroundDownloads() async {
        guard !offlineMode, !isDemo else { return }
        if let api { await downloads.configureBackground(api: api); await downloads.reload() }
    }
    @discardableResult
    func connect(_ newProfile: ServerProfile, password: String) async -> Bool {
        guard !busy, !switchingOffline, !Task.isCancelled else { return false }; busy = true; connectionError = nil
        defer { busy = false }
        do {
            let (client, status) = try await ReaderAPI.connect(profile: newProfile, password: password)
            let result: LibraryResponse = try await client.get("/v1/library")
            try Task.checkCancellation()
            try PasswordStore.save(password)
            var accepted = newProfile; accepted.instanceID = status.instanceId
            if (profile.instanceID != accepted.instanceID || profile.username != accepted.username), let previous = api {
                await ReaderPush.shared.disconnect(client: previous)
            }
            let stored = try JSONEncoder().encode(accepted)
            UserDefaults.standard.set(stored, forKey: "serverProfile")
            UserDefaults.standard.set(client.base.absoluteString, forKey: "downloadEndpoint")
            await downloads.activate(offlineAccount(accepted))
            await downloads.configureBackground(api: client)
            profile = accepted; api = client; isDemo = false; offlineMode = false; automaticOffline = false; library = result.items; covers.removeAllObjects()
            resetBookmarkSession(); readingStateWritable = status.readingStateWritable == true
            followingWritable = status.followingWritable == true
            pushNotificationsAvailable = status.pushNotificationsAvailable == true
            restoreFollows()
            if let account = downloads.account {
                do { try await downloads.store.setBookmarkWritable(readingStateWritable, account: account) }
                catch { bookmarkFailure = ("Impossibile salvare i segnalibri per l’uso offline. %@", error) }
            }
            await restoreCachedBookmarks()
            UserDefaults.standard.removeObject(forKey: "demoMode")
            UserDefaults.standard.removeObject(forKey: "offlineReading")
            endpointHost = client.base.host
            showConnection = false
            await refreshBookmarks()
            await refreshFollows()
            await ReaderPush.shared.synchronize()
            return true
        } catch {
            guard !Task.isCancelled, !ReaderCancellation.isCancellation(error) else { return false }
            connectionError = error
            // A failed attempt to connect to another account must not change
            // the current account's mode or its pending bookmark journal.
            if newProfile == profile,
               OfflineConnectivity.isReachabilityFailure(error), downloads.items.contains(where: \.complete),
               !UserDefaults.standard.bool(forKey: "offlineReading") {
                await useOffline(automatic: true)
            }
            if api == nil, !downloads.items.isEmpty {
                offlineMode = true; library = downloadedSeries; showConnection = false
            }
            return false
        }
    }
    func refresh() async {
        guard !busy, !refreshing, !switchingOffline, !Task.isCancelled else { return }
        // Pull-to-refresh while offline must not silently reconnect.
        if offlineMode { await downloads.reload(); await restoreCachedBookmarks(); return }
        if isDemo { refreshNotice = L10n.text("Tankarr aggiornato"); return }
        guard let client = api else { await reconnect(); return }
        refreshing = true; refreshNotice = nil
        defer { refreshing = false }
        do {
            let result: LibraryResponse = try await client.get("/v1/library", reload: true)
            try Task.checkCancellation()
            guard client === api, !offlineMode else { return }
            library = result.items; covers.removeAllObjects(); connectionError = nil
            await refreshBookmarks(); await refreshFollows()
            refreshNotice = L10n.text("Tankarr aggiornato")
        } catch {
            guard !Task.isCancelled, !ReaderCancellation.isCancellation(error), client === api else { return }
            if OfflineConnectivity.isReachabilityFailure(error) {
                // Only an actual network change requires selecting LAN/HTTPS again.
                await reconnect()
            } else { connectionError = error }
        }
    }

    func configuration() -> ReaderConfiguration {
        ReaderConfiguration(profile: profile, appLanguage: appLanguage,
            readingOptions: readingPreferences.snapshot(instance: progressInstance),
            followedSeries: Array(followedSeries))
    }

    func applyConfiguration(_ imported: ImportedReaderConfiguration) async {
        guard imported.includesPreferences else { return }
        let value = imported.configuration
        setLanguage(value.appLanguage)
        // Per-book choices and follows must never cross a server/account boundary.
        guard value.matchesAccount(profile), !isDemo, !offlineMode else { return }
        try? readingPreferences.merge(value.readingOptions, instance: progressInstance)
        await mergeFollowedSeries(value.followedSeries)
    }
    func reconnect() async {
        if isDemo { await startDemo(); return }
        guard let password = PasswordStore.read() else { showConnection = true; return }
        await connect(profile, password: password) // Re-evaluate LAN/HTTPS availability on refresh.
    }
    func disconnect() async {
        guard !busy, !switchingOffline else { return }; busy = true
        defer { busy = false }
        let wasWritable = readingStateWritable
        // A response from the old session must not recreate its journal after logout.
        resetBookmarkSession(); readingStateWritable = false
        do {
            try await downloads.removeAll()
            if let current = downloads.account {
                try await downloads.store.removeAll(account: current, includingBookmarks: true)
            }
            if let saved = offlineAccount(profile), saved != downloads.account {
                try await downloads.store.removeAll(account: saved, includingBookmarks: true)
            }
        }
        catch {
            readingStateWritable = wasWritable
            await restoreCachedBookmarks()
            connectionError = error; return
        }
        await downloads.activate(nil)
        await ReaderPush.shared.disconnect(client: api)
        clearFollowSnapshot()
        PasswordStore.remove(); UserDefaults.standard.removeObject(forKey: "serverProfile")
        UserDefaults.standard.removeObject(forKey: "demoMode")
        UserDefaults.standard.removeObject(forKey: "offlineReading")
        UserDefaults.standard.removeObject(forKey: "downloadEndpoint")
        api = nil; isDemo = false; offlineMode = false; automaticOffline = false; library = []; covers.removeAllObjects(); profile = ServerProfile()
        resetBookmarkSession(); readingStateWritable = false
        followingWritable = false; pushNotificationsAvailable = false; followedSeries = []
        followingError = nil; followingBusy = []; pendingPushSeriesID = nil
        endpointHost = nil; connectionError = nil; showConnection = true
    }
    private func offlineAccount(_ profile: ServerProfile) -> OfflineAccount? {
        guard let instance = profile.instanceID, !profile.username.isEmpty else { return nil }
        return OfflineAccount(instance: instance, username: profile.username)
    }
    private var downloadedSeries: [LibrarySeries] {
        OfflineLibrary.series(downloads.items)
    }
    func useOffline(automatic: Bool = false) async {
        guard !switchingOffline else { return }
        switchingOffline = true
        defer { switchingOffline = false }
        if !offlineMode { await cacheBookmarks() }
        offlineMode = true; automaticOffline = automatic
        // Only a deliberate offline selection persists across launches.
        UserDefaults.standard.set(!automatic, forKey: "offlineReading")
        await downloads.pauseAll(preserveQueue: true)
        api = nil; offlineMode = true; library = downloadedSeries; covers.removeAllObjects()
        sessionID = UUID(); bookmarksLoading = false; bookmarkBusy = false
        readingStateWritable = false; connectionError = nil; showConnection = false
        await restoreCachedBookmarks()
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
        guard !busy, !switchingOffline else { return }
        await downloads.activate(OfflineAccount(instance: DemoCatalog.instanceID, username: "demo"))
        api = nil; isDemo = true; offlineMode = false; automaticOffline = false; library = DemoCatalog.series; covers.removeAllObjects()
        followingWritable = false; pushNotificationsAvailable = false; restoreFollows(); pendingPushSeriesID = nil
        resetBookmarkSession(); readingStateWritable = false; bookmarks = demoBookmarks.all()
        await cacheBookmarks()
        connectionError = nil; endpointHost = nil; showConnection = false
        UserDefaults.standard.set(true, forKey: "demoMode")
        UserDefaults.standard.removeObject(forKey: "offlineReading")
    }
    private func resetBookmarkSession() {
        sessionID = UUID(); bookmarks = []; bookmarkFailure = nil; bookmarksLoading = false
        bookmarkBusy = false; pendingBookmarkSeries = []; offlineBookmarkWritable = false
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
            let saved = try await downloads.store.bookmarkState(account: account)
            guard downloads.account == account, sessionID == session else { return }
            bookmarks = saved.visible; offlineBookmarkWritable = saved.writable
            pendingBookmarkSeries = Set(saved.pending.map(\.seriesID))
        } catch {
            if downloads.account == account, sessionID == session {
                bookmarkFailure = ("Impossibile leggere i segnalibri offline. %@", error)
            }
        }
    }
    func refreshBookmarks() async {
        guard !bookmarkBusy, !bookmarksLoading else { return }
        if offlineMode && !isDemo { await restoreCachedBookmarks(); return }
        if isDemo { bookmarks = demoBookmarks.all(); bookmarkFailure = nil; await cacheBookmarks(); return }
        guard readingStateWritable, let client = api, let account = downloads.account else { return }
        let session = sessionID
        bookmarksLoading = true
        defer { if sessionID == session { bookmarksLoading = false } }
        do {
            try await sendPendingBookmarks(client: client, account: account, session: session)
            guard sessionID == session else { return }
            let result: BookmarksResponse = try await client.get("/v1/bookmarks")
            guard sessionID == session else { return }
            try await downloads.store.saveBookmarks(result.items, account: account)
            await restoreCachedBookmarks(); bookmarkFailure = nil
        } catch {
            if sessionID == session, !Task.isCancelled {
                await restoreCachedBookmarks()
                bookmarkFailure = (pendingBookmarkSeries.isEmpty ? "Impossibile aggiornare i segnalibri. %@" :
                    "Modifiche salvate sul dispositivo. Sincronizzazione non riuscita: %@", error)
            }
        }
    }
    private func sendPendingBookmarks(client: ReaderAPI, account: OfflineAccount, session: UUID) async throws {
        while sessionID == session, downloads.account == account, !offlineMode, readingStateWritable {
            try Task.checkCancellation()
            let state = try await downloads.store.bookmarkState(account: account)
            guard let change = state.pending.first, sessionID == session,
                  downloads.account == account, !offlineMode, readingStateWritable else { return }
            let confirmed: ReaderBookmark?
            if let value = change.value {
                confirmed = try await client.saveBookmark(series: change.seriesID, book: value.bookId, page: value.pageIndex)
            } else {
                try await client.removeBookmark(series: change.seriesID); confirmed = nil
            }
            guard sessionID == session, downloads.account == account else { return }
            try await downloads.store.acknowledgeBookmark(change.id, confirmed: confirmed, account: account)
        }
    }
    func saveBookmark(_ book: ReaderBook, page: Int) async {
        guard canUseBookmarks, !busy, !bookmarkBusy, !bookmarksLoading, let series = book.seriesId,
              (0..<book.pageCount).contains(page), let account = downloads.account else { return }
        let session = sessionID
        let demo = isDemo
        var stored = false
        bookmarkBusy = true; bookmarkFailure = nil
        defer { if sessionID == session { bookmarkBusy = false } }
        do {
            let saved = ReaderBookmark(seriesId: series, seriesTitle: book.seriesTitle, bookId: book.id,
                label: book.title, pageIndex: page, updatedAt: ISO8601DateFormatter().string(from: Date()))
            if demo {
                demoBookmarks.save(saved)
                bookmarks = demoBookmarks.all(); await cacheBookmarks()
            } else {
                try await downloads.store.queueBookmark(seriesID: series, value: saved, account: account)
                stored = true
                guard sessionID == session else { return }
                await restoreCachedBookmarks()
                if let client = api, !offlineMode {
                    try await sendPendingBookmarks(client: client, account: account, session: session)
                    guard sessionID == session else { return }
                    await restoreCachedBookmarks()
                }
            }
        } catch {
            if sessionID == session {
                bookmarkFailure = (stored ? "Modifiche salvate sul dispositivo. Sincronizzazione non riuscita: %@" :
                    "Impossibile salvare il segnalibro sul dispositivo. %@", error)
            }
        }
    }
    func removeBookmark(_ bookmark: ReaderBookmark) async {
        guard canUseBookmarks, !busy, !bookmarkBusy, !bookmarksLoading, let account = downloads.account else { return }
        let session = sessionID
        let demo = isDemo
        var stored = false
        bookmarkBusy = true; bookmarkFailure = nil
        defer { if sessionID == session { bookmarkBusy = false } }
        do {
            if demo {
                demoBookmarks.remove(series: bookmark.seriesId)
                bookmarks = demoBookmarks.all(); await cacheBookmarks()
            } else {
                try await downloads.store.queueBookmark(seriesID: bookmark.seriesId, value: nil, account: account)
                stored = true
                guard sessionID == session else { return }
                await restoreCachedBookmarks()
                if let client = api, !offlineMode {
                    try await sendPendingBookmarks(client: client, account: account, session: session)
                    guard sessionID == session else { return }
                    await restoreCachedBookmarks()
                }
            }
        } catch {
            if sessionID == session {
                bookmarkFailure = (stored ? "Modifiche salvate sul dispositivo. Sincronizzazione non riuscita: %@" :
                    "Impossibile salvare il segnalibro sul dispositivo. %@", error)
            }
        }
    }
    func books(for series: String) async throws -> [LibraryBook] {
        if offlineMode { return OfflineLibrary.books(seriesID: series, downloads: downloads.items) }
        if isDemo { return try DemoCatalog.books(for: series) }
        guard let api else { throw ReaderError.unavailable(0) }
        do {
            let result: BooksResponse = try await api.get("/v1/series/\(try Endpoint.identifier(series))")
            return result.books
        } catch {
            await fallBackOffline(error, client: api)
            if offlineMode { return OfflineLibrary.books(seriesID: series, downloads: downloads.items) }
            throw error
        }
    }
    func book(_ id: String) async throws -> ReaderBook {
        if let account = downloads.account, let cached = try await downloads.store.book(id, account: account) { return cached }
        if offlineMode { throw OfflineError.notDownloaded }
        if isDemo { return try DemoCatalog.book(id) }
        guard let api else { throw ReaderError.unavailable(0) }
        do { return try await api.get("/v1/books/\(try Endpoint.identifier(id))") }
        catch { await fallBackOffline(error, client: api); throw error }
    }
    func page(_ id: String, at index: Int) async throws -> UIImage {
        if let account = downloads.account, let data = try await downloads.store.page(id, index: index, account: account) {
            guard let image = UIImage(data: data) else { throw OfflineError.incomplete }
            return image
        }
        if offlineMode { throw OfflineError.notDownloaded }
        if isDemo { return DemoArtwork.page(try DemoCatalog.page(id, at: index)) }
        guard let api else { throw ReaderError.unavailable(0) }
        let data: Data
        do { data = try await api.data("/v1/books/\(try Endpoint.identifier(id))/pages/\(index)") }
        catch { await fallBackOffline(error, client: api); throw error }
        guard let image = UIImage(data: data) else { throw ReaderError.unavailable(415) }
        return image
    }
}
