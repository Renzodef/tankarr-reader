import SwiftUI
import Security
import UIKit
import Network
import ImageIO

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
                    } else if phase == .background {
                        model.enteredBackground()
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
    @Published private(set) var coverRevision = UUID()
    @Published private(set) var imageSession = UUID()
    @Published var refreshNotice: String?
    @Published private var connectionError: Error?
    @Published var showConnection = false
    @Published private var endpointHost: String?
    @Published var isDemo = false
    @Published private(set) var appLanguage = AppLanguage.system
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
    var canBrowse: Bool { api != nil || isDemo || offlineMode || !library.isEmpty }
    var canUseBookmarks: Bool { isDemo || (offlineMode ? offlineBookmarkWritable : readingStateWritable) }
    var canViewBookmarks: Bool { offlineMode || canUseBookmarks || !pendingBookmarkSeries.isEmpty }
    var visibleLibrary: [LibrarySeries] { offlineMode && !automaticOffline ? downloadedSeries : library }
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
    private let pages = NSCache<NSString, UIImage>()
    let localStorage = ReaderLocalStorage(root: FileManager.default.urls(for: .applicationSupportDirectory,
        in: .userDomainMask)[0].appendingPathComponent("SavedLibrary", isDirectory: true))
    @Published private(set) var storageNotice: String?
    @Published private(set) var storageRefreshProgress: Int?
    @Published private(set) var localStorageRevision = UUID()
    private var coverWarmup: Task<Void, Never>?
    private var coverWarmupPaused = false
    private var inBackground = false
    private var lastLibrarySync: Date?
    private var coverVersions: [String: String] = [:]
    private var bookVersions: [String: String] = [:]

    private func stopCoverWarmup() {
        coverWarmup?.cancel()
        coverWarmup = nil
    }

    private func resetCovers() {
        stopCoverWarmup()
        covers.removeAllObjects(); pages.removeAllObjects(); bookVersions.removeAll()
        coverRevision = UUID(); imageSession = UUID()
    }
    private func publishLibrary(_ items: [LibrarySeries]) {
        let changed = Dictionary(items.compactMap { item in item.coverRevision.map { (item.id, $0) } },
                                 uniquingKeysWith: { first, _ in first })
        let artworkChanged = coverVersions != changed
        let seriesChanged = library.map(\.id) != items.map(\.id)
        if artworkChanged || seriesChanged { stopCoverWarmup() }
        coverVersions = changed
        if library != items { library = items }
        if artworkChanged { coverRevision = UUID() }
        warmCovers()
    }
    private func remember<T: Encodable>(_ value: T, key: String, account: OfflineAccount, generation: UUID) async {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? await localStorage.write(data, to: .catalogue, key: key, account: account, generation: generation)
    }
    private func recalled<T: Decodable>(_ type: T.Type, key: String, account: OfflineAccount) async -> T? {
        guard let data = await localStorage.read(.catalogue, key, account: account) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private let progress = ReadingProgress()
    private let readingPreferences = ReadingPreferences()
    private let languagePreferences = AppLanguagePreferences()
    private let demoBookmarks = DemoBookmarkStore()
    private let networkMonitor = NWPathMonitor()
    private var networkAvailable: Bool?
    private var networkAllowsPrefetch = false
    private var switchingOffline = false
    private var clearingImages = false

    init() {
        appLanguage = languagePreferences.language
        L10n.language = appLanguage
        covers.totalCostLimit = 32 * 1024 * 1024
        covers.countLimit = 100
        pages.totalCostLimit = 64 * 1024 * 1024
        pages.countLimit = 3
        if let data = UserDefaults.standard.data(forKey: "serverProfile"),
           let saved = try? JSONDecoder().decode(ServerProfile.self, from: data) { profile = saved }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status != .unsatisfied
            let allowsPrefetch = path.status == .satisfied && !path.isConstrained && !path.isExpensive
            Task { @MainActor [weak self] in
                self?.networkAllowsPrefetch = allowsPrefetch
                await self?.networkChanged(available: available)
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "reader-connectivity"))
    }
    private func networkChanged(available: Bool) async {
        let changed = networkAvailable != available
        networkAvailable = available
        if available { warmCovers() }
        else { stopCoverWarmup() }
        guard changed, restored, !isDemo, !busy else { return }
        if available {
            if automaticOffline { await reconnect() }
        } else if api != nil && !offlineMode && canBrowse {
            await useOffline(automatic: true)
        }
    }
    func enteredBackground() {
        inBackground = true
        stopCoverWarmup()
    }

    func becameActive() async {
        inBackground = false
        if appLanguage == .system { objectWillChange.send() }
        if automaticOffline, networkAvailable != false { await reconnect() }
        warmCovers()
        await resumeBackgroundDownloads()
        await refreshBookmarks()
        await refreshFollows()
        await ReaderPush.shared.synchronize()
        if let lastLibrarySync, Date().timeIntervalSince(lastLibrarySync) >= 60, !offlineMode, api != nil {
            await refresh(force: false)
        }
    }
    private func fallBackOffline(_ error: Error, client: ReaderAPI? = nil) async {
        guard !Task.isCancelled, !busy, !isDemo, !offlineMode,
              client == nil || client === api,
              OfflineConnectivity.isReachabilityFailure(error),
              !library.isEmpty || downloads.items.contains(where: \.complete) else { return }
        await useOffline(automatic: true)
    }
    func setLanguage(_ language: AppLanguage) {
        guard appLanguage != language else { return }
        L10n.language = language
        languagePreferences.language = language
        appLanguage = language
        Task { await ReaderPush.shared.synchronize() }
    }
    func restore() async {
        guard !restored else { return }; restored = true
        Task.detached(priority: .utility) { [localStorage] in
            localStorage.removeLegacyPages()
        }
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
        if let account = downloads.account, PasswordStore.read() != nil,
           let snapshot = await recalled([LibrarySeries].self, key: "library", account: account), !snapshot.isEmpty {
            publishLibrary(snapshot)
        } else if !downloads.items.isEmpty {
            offlineMode = true; publishLibrary(downloadedSeries)
        }
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
            let storageGeneration = await localStorage.generation()
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
            let accountChanged = isDemo || offlineAccount(profile) != downloads.account
            let wasDisconnected = api == nil
            stopCoverWarmup()
            profile = accepted; api = client; isDemo = false; offlineMode = false; automaticOffline = false
            if accountChanged { resetCovers(); coverWarmupPaused = false }
            if wasDisconnected { coverRevision = UUID() }
            lastLibrarySync = Date()
            publishLibrary(result.items)
            if let account = downloads.account {
                await remember(result.items, key: "library", account: account, generation: storageGeneration)
            }
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
               OfflineConnectivity.isReachabilityFailure(error), canBrowse,
               !UserDefaults.standard.bool(forKey: "offlineReading") {
                await useOffline(automatic: true)
            }
            if api == nil, !offlineMode, !downloads.items.isEmpty {
                offlineMode = true; library = downloadedSeries; showConnection = false
            }
            return false
        }
    }
    func refresh(force: Bool = true) async {
        guard !busy, !refreshing, !switchingOffline, storageRefreshProgress == nil, !Task.isCancelled else { return }
        // Pull-to-refresh while offline must not silently reconnect.
        if offlineMode { await downloads.reload(); await restoreCachedBookmarks(); return }
        if isDemo { refreshNotice = L10n.text("Tankarr aggiornato"); return }
        guard let client = api else { await reconnect(); return }
        refreshing = true; refreshNotice = nil
        defer { refreshing = false }
        do {
            let storageGeneration = await localStorage.generation()
            let result: LibraryResponse = try await client.get("/v1/library", reload: force)
            try Task.checkCancellation()
            guard client === api, !offlineMode else { return }
            lastLibrarySync = Date()
            publishLibrary(result.items); connectionError = nil
            if let account = downloads.account {
                await remember(result.items, key: "library", account: account, generation: storageGeneration)
            }
            await refreshBookmarks(); await refreshFollows()
            if force { refreshNotice = L10n.text("Tankarr aggiornato") }
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
        clearingImages = true; resetCovers()
        defer { busy = false; clearingImages = false; coverRevision = UUID() }
        let wasWritable = readingStateWritable
        // A response from the old session must not recreate its journal after logout.
        resetBookmarkSession(); readingStateWritable = false
        do {
            try await downloads.removeAll()
            if let current = downloads.account {
                try await downloads.store.removeAll(account: current, includingBookmarks: true)
                try await localStorage.clear(account: current)
            }
            if let saved = offlineAccount(profile), saved != downloads.account {
                try await downloads.store.removeAll(account: saved, includingBookmarks: true)
                try await localStorage.clear(account: saved)
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
        api = nil; isDemo = false; offlineMode = false; automaticOffline = false; publishLibrary([]); resetCovers(); profile = ServerProfile()
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
        api = nil; offlineMode = true; resetCovers()
        sessionID = UUID(); bookmarksLoading = false; bookmarkBusy = false
        readingStateWritable = false; connectionError = nil; showConnection = false
        await restoreCachedBookmarks()
    }
    func cover(_ id: String) async -> UIImage? {
        guard !clearingImages, !Task.isCancelled else { return nil }
        let session = imageSession
        let revision = coverVersions[id]
        let key = "\(id):\(revision ?? "")" as NSString
        if let cached = covers.object(forKey: key) { return cached }
        if isDemo, let series = DemoCatalog.series.first(where: { $0.id == id }) {
            let image = DemoArtwork.cover(series)
            covers.setObject(image, forKey: key, cost: 600 * 900 * 4)
            return image
        }
        guard let account = downloads.account else { return nil }
        var data = await localStorage.read(.covers, id, account: account, revision: revision)
        var image: UIImage?
        if let data { image = await Self.coverThumbnail(data) }
        if image == nil, !offlineMode, let client = api {
            data = try? await fetchCover(id, revision: revision, account: account, client: client, requireSave: false)
            if let data { image = await Self.coverThumbnail(data) }
        }
        let currentImage = image != nil
        if image == nil {
            // Keep the previous cover visible if the new revision is temporarily unreachable.
            data = await localStorage.read(.covers, id, account: account)
            if data == nil { data = try? await downloads.store.cover(seriesID: id, account: account) }
            if let data { image = await Self.coverThumbnail(data) }
        }
        guard let image, let data, !Task.isCancelled, session == imageSession,
              revision == coverVersions[id], account == downloads.account else { return nil }
        if currentImage {
            covers.setObject(image, forKey: key, cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count)
        }
        return image
    }
    private func fetchCover(_ id: String, revision: String?, account: OfflineAccount,
                            client: ReaderAPI, force: Bool = false, requireSave: Bool = true, preloading: Bool = false) async throws -> Data {
        let generation = await localStorage.generation()
        let data = try await client.cover(id, reload: force || revision != nil, preloading: preloading)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw ReaderError.unavailable(415) }
        try Task.checkCancellation()
        guard client === api, account == downloads.account, revision == coverVersions[id], !clearingImages
        else { throw CancellationError() }
        do {
            try await localStorage.write(data, to: .covers, key: id, account: account,
                                         generation: generation, revision: revision)
        } catch OfflineError.lowSpace {
            storageNotice = OfflineError.lowSpace.localizedDescription
            if requireSave { throw OfflineError.lowSpace }
        } catch { if requireSave { throw error } }
        return data
    }
    private func warmCovers() {
        guard coverWarmup == nil, !coverWarmupPaused, storageRefreshProgress == nil, !clearingImages,
              networkAvailable != false, !inBackground, !isDemo, !offlineMode, !library.isEmpty,
              let client = api, let account = downloads.account else { return }
        let items = library
        // One request at a time leaves the other cover connection available
        // for the visible grid. The pass is independent of the visible cells.
        coverWarmup = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            var saved = false
            defer {
                if !Task.isCancelled {
                    coverWarmup = nil
                    if saved { localStorageRevision = UUID() }
                }
            }
            for item in items {
                guard !Task.isCancelled, client === api, account == downloads.account else { return }
                if await localStorage.contains(.covers, item.id, account: account, revision: item.coverRevision) { continue }
                do {
                    _ = try await fetchCover(item.id, revision: item.coverRevision, account: account,
                                             client: client, preloading: true)
                    saved = true
                } catch OfflineError.lowSpace { return }
                catch { if Task.isCancelled { return } }
            }
        }
    }
    func clearSaved(_ section: ReaderStorageSection) async {
        guard !clearingImages, !busy, storageRefreshProgress == nil, let account = downloads.account else { return }
        clearingImages = true
        if section == .covers { coverWarmupPaused = true }
        resetCovers()
        defer {
            clearingImages = false
            coverWarmup = nil
            coverRevision = UUID()
            localStorageRevision = UUID()
        }
        storageNotice = nil
        do { try await localStorage.clear(section, account: account) }
        catch { storageNotice = error.localizedDescription }
    }
    func refreshSaved() async {
        guard let client = api, let account = downloads.account, !offlineMode, !isDemo,
              !busy, !refreshing, !clearingImages, storageRefreshProgress == nil else { return }
        stopCoverWarmup()
        coverWarmupPaused = false
        storageRefreshProgress = 0; storageNotice = nil
        defer {
            storageRefreshProgress = nil; coverRevision = UUID(); localStorageRevision = UUID()
            warmCovers()
        }
        do {
            let generation = await localStorage.generation()
            let result: LibraryResponse = try await client.get("/v1/library", reload: true)
            guard !Task.isCancelled, client === api, account == downloads.account else { return }
            lastLibrarySync = Date()
            publishLibrary(result.items)
            await remember(result.items, key: "library", account: account, generation: generation)
            var failed = 0
            for item in result.items {
                guard !Task.isCancelled, client === api, account == downloads.account else { return }
                do { _ = try await fetchCover(item.id, revision: item.coverRevision, account: account, client: client, force: true) }
                catch ReaderError.unavailable(404) { /* No cover on the server. */ }
                catch OfflineError.lowSpace { return }
                catch { failed += 1 }
                if let progress = storageRefreshProgress { storageRefreshProgress = progress + 1 }
            }
            covers.removeAllObjects()
            storageNotice = failed == 0 ? L10n.text("Dati salvati aggiornati") : L10n.format("%d copertine non aggiornate", failed)
        } catch {
            if !Task.isCancelled { storageNotice = error.localizedDescription }
        }
    }
    private nonisolated static func coverThumbnail(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
                let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 600,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        }.value
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
        api = nil; isDemo = true; offlineMode = false; automaticOffline = false; library = DemoCatalog.series; resetCovers()
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
    func savedBooks(for series: String) async -> [LibraryBook]? {
        guard let account = downloads.account, !isDemo, !offlineMode || automaticOffline else { return nil }
        return await recalled([LibraryBook].self, key: "series-\(series)", account: account)
    }
    func books(for series: String) async throws -> [LibraryBook] {
        if isDemo && !offlineMode { return try DemoCatalog.books(for: series) }
        guard !offlineMode, let api else {
            return await savedBooks(for: series) ?? OfflineLibrary.books(seriesID: series, downloads: downloads.items)
        }
        let generation = await localStorage.generation()
        do {
            let result: BooksResponse = try await api.get("/v1/series/\(try Endpoint.identifier(series))")
            try Task.checkCancellation()
            guard self.api === api else { throw CancellationError() }
            if let account = downloads.account {
                await remember(result.books, key: "series-\(series)", account: account, generation: generation)
            }
            return result.books
        } catch {
            await fallBackOffline(error, client: api)
            if let saved = await savedBooks(for: series) { return saved }
            if offlineMode { return OfflineLibrary.books(seriesID: series, downloads: downloads.items) }
            throw error
        }
    }
    func book(_ id: String) async throws -> ReaderBook {
        if let account = downloads.account, let downloaded = try await downloads.store.book(id, account: account) { return downloaded }
        if isDemo && !offlineMode { return try DemoCatalog.book(id) }
        if let account = downloads.account, !offlineMode,
           let book = await recalled(ReaderBook.self, key: "book-\(id)", account: account) {
            bookVersions[id] = book.contentRevision
            return book
        }
        if offlineMode || api == nil { throw OfflineError.notDownloaded }
        return try await refreshBook(id)
    }
    func refreshBook(_ id: String) async throws -> ReaderBook {
        guard let api, !offlineMode, !isDemo else { throw ReaderError.unavailable(0) }
        let generation = await localStorage.generation()
        do {
            let book: ReaderBook = try await api.get("/v1/books/\(try Endpoint.identifier(id))")
            try Task.checkCancellation()
            guard self.api === api else { throw CancellationError() }
            bookVersions[id] = book.contentRevision
            if let account = downloads.account {
                await remember(book, key: "book-\(id)", account: account, generation: generation)
            }
            return book
        } catch { await fallBackOffline(error, client: api); throw error }
    }
    func prepareNextPage(_ id: String, after index: Int, pageCount: Int) async {
        guard index >= 0, index < pageCount - 1,
              !ProcessInfo.processInfo.isLowPowerModeEnabled,
              networkAllowsPrefetch || downloads.item(id)?.complete == true else { return }
        let generation = imageSession
        do {
            // Let navigation settle before spending bandwidth on one nearby page.
            try await Task.sleep(for: .milliseconds(150))
            guard generation == imageSession else { return }
            _ = try await page(id, at: index + 1, speculative: true)
        } catch { /* Optional work must not interrupt reading or switch accounts/offline mode. */ }
    }
    func page(_ id: String, at index: Int, speculative: Bool = false) async throws -> UIImage {
        try Task.checkCancellation()
        guard !clearingImages else { throw CancellationError() }
        let revision = bookVersions[id]
        let downloaded = downloads.item(id)?.complete == true
        let cacheKey = "\(id):\(downloaded):\(revision ?? ""):\(index)" as NSString
        if (!offlineMode || downloaded), let cached = pages.object(forKey: cacheKey) { return cached }
        let generation = imageSession
        let account = downloads.account
        let localCopy: Data?
        if let account { localCopy = try await downloads.store.page(id, index: index, account: account) }
        else { localCopy = nil }
        if isDemo, localCopy == nil, !offlineMode { return DemoArtwork.page(try DemoCatalog.page(id, at: index)) }
        let client = api
        let data: Data
        if let localCopy { data = localCopy }
        else {
            guard !offlineMode, let client else { throw OfflineError.notDownloaded }
            do { data = try await client.downloadPage(book: id, index: index) }
            catch {
                if !speculative { await fallBackOffline(error, client: client) }
                throw error
            }
        }
        guard let image = UIImage(data: data) else { throw ReaderError.unavailable(415) }
        let prepared = await image.byPreparingForDisplay() ?? image
        try Task.checkCancellation()
        guard generation == imageSession, account == downloads.account, revision == bookVersions[id]
        else { throw CancellationError() }
        pages.setObject(prepared, forKey: cacheKey, cost: prepared.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count)
        return prepared
    }
}
