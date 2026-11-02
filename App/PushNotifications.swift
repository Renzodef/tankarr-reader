import Foundation
import Security
import UIKit
import UserNotifications

/// Native APNs registration. No notification watcher, silent-push loop or
/// background fetch: iOS delivers alerts even when Reader is not running.
@MainActor
final class ReaderPush: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ReaderPush()
    @Published var denied = false
    @Published var notice: String?
    private(set) var token: String?
    private var lastRegistration: String?
    var deviceID: UUID {
        if let value = UserDefaults.standard.string(forKey: "push.installation.v1"), let id = UUID(uuidString: value) { return id }
        let id = UUID(); UserDefaults.standard.set(id.uuidString, forKey: "push.installation.v1"); return id
    }
    var environment: PushEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }
    func installDelegate() { UNUserNotificationCenter.current().delegate = self }
    func receiveToken(_ value: Data) async {
        let incoming = value.map { String(format: "%02x", $0) }.joined()
        if token != incoming { token = incoming; lastRegistration = nil }
        await synchronize()
    }
    func requestPermission() async {
        guard !AppModel.shared.isDemo, AppModel.shared.pushNotificationsAvailable else { return }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            denied = !granted
            if granted { await synchronize() }
        } catch { notice = L10n.text("Impossibile attivare le notifiche. Riprova dalle impostazioni.") }
    }
    func synchronize() async {
        let model = AppModel.shared
        guard !model.isDemo, !model.offlineMode, model.pushNotificationsAvailable, let api = model.api else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        denied = settings.authorizationStatus == .denied
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            if denied { try? await api.unregisterPush(device: deviceID); lastRegistration = nil }
            return
        }
        guard let token else { UIApplication.shared.registerForRemoteNotifications(); return }
        let language = model.appLanguage.code()
        let stamp = [model.profile.instanceID ?? "", model.profile.username, token, language].joined(separator: "\n")
        guard stamp != lastRegistration else { return }
        do {
            try await api.registerPush(device: deviceID, token: token, environment: environment, language: language)
            guard api === model.api else { return }
            if language != model.appLanguage.code() {
                lastRegistration = nil
                await synchronize()
                return
            }
            lastRegistration = stamp; notice = nil
        } catch { notice = L10n.text("Registrazione notifiche in attesa. Riprova tornando online.") }
    }
    func disconnect(client: ReaderAPI?) async {
        if let client { try? await client.unregisterPush(device: deviceID) }
        UIApplication.shared.unregisterForRemoteNotifications()
        lastRegistration = nil; token = nil; notice = nil
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        Task { @MainActor in
            let model = AppModel.shared
            let valid = !model.isDemo && ChapterNotification(payload: info, instance: model.profile.instanceID, username: model.profile.username) != nil
            completionHandler(valid ? [.banner, .sound, .list] : [])
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            let model = AppModel.shared
            if !model.isDemo, let message = ChapterNotification(payload: info, instance: model.profile.instanceID, username: model.profile.username) {
                model.pendingPushSeriesID = message.seriesID
            }
            completionHandler()
        }
    }
}
