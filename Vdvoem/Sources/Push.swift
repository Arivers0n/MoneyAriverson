import SwiftUI
import UIKit
import UserNotifications
import BackgroundTasks

extension Notification.Name {
    static let vdPushToken = Notification.Name("vd.pushToken")
}

/// Системные уведомления Apple: чат, ход в игре, сигналы и т.д. приходят, даже когда приложение закрыто.
/// Если пуши недоступны (нет сертификата с Push или сервер ещё не настроен), работает запасной вариант:
/// iOS изредка будит приложение, оно проверяет новое и показывает местное уведомление.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let s = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(s, forKey: "vd.apns")
        NotificationCenter.default.post(name: .vdPushToken, object: s)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set(false, forKey: "vd.pushOK")
    }

    // Приложение открыто — данные и так приходят вживую, баннер не нужен.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }

    // Нажали на уведомление — открываем нужный раздел.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let open = info["open"] as? String, let url = URL(string: "vdvoem://\(open)") else { return }
        await MainActor.run { UIApplication.shared.open(url) }
    }
}

enum Push {
    static let refreshID = "ru.vdvoem.app.refresh"
    static var token: String? { UserDefaults.standard.string(forKey: "vd.apns") }
    /// Токен доставлен на сервер — запасной вариант не нужен.
    static var working: Bool { UserDefaults.standard.bool(forKey: "vd.pushOK") }

    /// Просит разрешение (один раз) и регистрируется в Apple.
    @MainActor static func enable() async {
        let c = UNUserNotificationCenter.current()
        var st = await c.notificationSettings().authorizationStatus
        if st == .notDetermined { _ = await Notifier.request(); st = await c.notificationSettings().authorizationStatus }
        guard st == .authorized || st == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    @MainActor static func upload(_ sync: SyncEngine) async {
        guard let t = token, sync.isPaired else { return }
        let ok = await sync.registerDevice(t)
        UserDefaults.standard.set(ok, forKey: "vd.pushOK")
    }

    // MARK: Запасной вариант

    static func scheduleRefresh() {
        let r = BGAppRefreshTaskRequest(identifier: refreshID)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    @MainActor static func fallbackCheck(_ sync: SyncEngine) async {
        scheduleRefresh()
        guard !working else { return }
        for n in await sync.backgroundCheck() {
            let c = UNMutableNotificationContent()
            c.title = n.0; c.body = n.1; c.sound = .default
            c.userInfo = ["open": n.2]
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }
}

extension SyncEngine {
    func registerDevice(_ token: String) async -> Bool {
        (try? await send("/api/vd/device", obj(["token": token]))) != nil
    }

    /// Для фонового запуска: догнать изменения и вернуть, что показать (заголовок, текст, раздел).
    func backgroundCheck() async -> [(String, String, String)] {
        guard pair != nil, let store else { return [] }
        let seen = Set(store.data.messages.map(\.id))
        let turns = Dictionary(uniqueKeysWithValues: store.data.matches.map { ($0.id, $0.moves) })
        try? await flush()
        try? await pull()
        var out: [(String, String, String)] = []
        let fresh = store.data.messages.filter { !seen.contains($0.id) && $0.from == .partner }.sorted { $0.date < $1.date }
        if let last = fresh.last {
            let t = last.kind == "voice" ? "🎤 Голосовое сообщение" : last.text
            out.append((store.name(.partner), fresh.count > 1 ? "\(fresh.count) новых · \(t)" : t, "chat"))
        }
        if let g = store.data.matches.first(where: { $0.state == .playing && $0.turn == .me && (turns[$0.id] ?? -1) < $0.moves }) {
            out.append((g.kind.title, "Ваш ход — \(store.name(.partner)) сходил(а)", "games"))
        }
        return out
    }
}
