import Foundation

@MainActor
extension AppModel {
    var canFollowSeries: Bool { isDemo || (!offlineMode && followingWritable && api != nil) }
    private var followsCacheKey: String? {
        if isDemo { return "reader.follows.demo.v1" }
        guard let instance = profile.instanceID else { return nil }
        return "reader.follows.v1." + OfflineAccount(instance: instance, username: profile.username).key
    }
    func restoreFollows() {
        followedSeries = followsCacheKey.flatMap { UserDefaults.standard.stringArray(forKey: $0) }.map(Set.init) ?? []
        followingBusy = []; followingError = nil
    }
    private func cacheFollows() {
        if let key = followsCacheKey { UserDefaults.standard.set(followedSeries.sorted(), forKey: key) }
    }
    func clearFollowSnapshot() {
        if let key = followsCacheKey { UserDefaults.standard.removeObject(forKey: key) }
        followedSeries = []
    }
    func refreshFollows() async {
        guard !isDemo, !offlineMode, followingWritable, let client = api else { return }
        do {
            let items = try await client.follows()
            guard client === api, !isDemo, !offlineMode else { return }
            followedSeries = Set(items.map(\.seriesId)); cacheFollows(); followingError = nil
        } catch {
            if client === api, !Task.isCancelled, !ReaderCancellation.isCancellation(error) {
                followingError = L10n.text("Impossibile aggiornare le serie seguite. Riprova.")
            }
        }
    }
    func toggleFollowing(_ series: String) async {
        guard canFollowSeries, !followingBusy.contains(series) else { return }
        followingBusy.insert(series); followingError = nil
        defer { followingBusy.remove(series) }
        let following = !followedSeries.contains(series)
        if isDemo {
            if following { followedSeries.insert(series) } else { followedSeries.remove(series) }
            cacheFollows(); return
        }
        guard let client = api else { return }
        do {
            let items = try await client.setFollowing(following, series: series)
            guard client === api, !isDemo else { return }
            followedSeries = Set(items.map(\.seriesId)); cacheFollows()
            if following { await ReaderPush.shared.requestPermission() }
        } catch { if client === api { followingError = L10n.text("Impossibile modificare le serie seguite. Riprova.") } }
    }

    func mergeFollowedSeries(_ series: [String]) async {
        guard canFollowSeries, !isDemo, let client = api else { return }
        let available = Set(library.map(\.id))
        for id in Set(series).intersection(available).subtracting(followedSeries).sorted() {
            guard !Task.isCancelled, client === api else { return }
            do {
                let items = try await client.setFollowing(true, series: id)
                guard client === api else { return }
                followedSeries = Set(items.map(\.seriesId)); cacheFollows()
            } catch {
                if !Task.isCancelled { followingError = L10n.text("Impossibile ripristinare tutte le serie seguite. Reimporta la configurazione per riprovare.") }
                return
            }
        }
        // iOS notification permission belongs to this device and is never imported.
        await ReaderPush.shared.synchronize()
    }
}
