import SwiftUI
import SwiftData
import UserNotifications

/// Нажатие на уведомление открывает нужный экран (например, голосовой ввод).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Быстрые действия при удержании иконки на рабочем столе
        application.shortcutItems = [
            UIApplicationShortcutItem(type: "voice", localizedTitle: "Записать голосом", localizedSubtitle: "Скажите, что потратили", icon: UIApplicationShortcutIcon(systemImageName: "mic.fill")),
            UIApplicationShortcutItem(type: "scan", localizedTitle: "Скан чека", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "doc.viewfinder")),
            UIApplicationShortcutItem(type: "add", localizedTitle: "Новая операция", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "plus.circle")),
            UIApplicationShortcutItem(type: "debts", localizedTitle: "Платежи", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "calendar")),
        ]
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { SceneDelegate.pending = item.type }
        let c = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s) {
            await MainActor.run { Router.shared.handle(url: url) }
        }
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    @MainActor static var pending: String?
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        SceneDelegate.open(shortcutItem.type)
        completionHandler(true)
    }
    @MainActor static func open(_ type: String) {
        if let url = URL(string: "koshelek://\(type)") { Router.shared.handle(url: url) }
    }
}

@main
struct KoshelekApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var router = Router.shared
    @StateObject private var sync = SyncEngine.shared
    @StateObject private var testData = TestData.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(sync)
                .modelContainer(testData.container ?? Store.container)
                .id(testData.mode?.rawValue ?? "real")
                .safeAreaInset(edge: .top, spacing: 0) { TestDataSwitch() }
                .onOpenURL { router.handle(url: $0) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var sync: SyncEngine
    @ObservedObject private var ap = Appearance.shared
    @ObservedObject private var cats = CategoryPrefs.shared
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var phase
    @Query private var qDebts: [Debt]
    private var debts: [Debt] { qDebts.live }
    @Query private var qTxs: [Tx]
    private var txs: [Tx] { qTxs.live }
    @Query private var qRecs: [Recurring]
    private var recs: [Recurring] { qRecs.live }


    @State private var showScan = false
    @State private var showWelcome = !SyncEngine.shared.loggedIn && !UserDefaults.standard.bool(forKey: "welcome.done")

    private func startScan() {
        guard Keychain.hasKey else {
            router.say("Для скана нужен ключ Claude API")
            router.show(.settings)
            return
        }
        showScan = true
    }

    private func scan(_ imgs: [Data]) {
        router.busy = imgs.count > 1 ? "Claude читает \(imgs.count) \(plural(imgs.count, "картинку", "картинки", "картинок"))…" : "Claude читает чек…"
        Task {
            defer { router.busy = nil }
            do {
                let items = try await Brain.parseReceipts(imgs, ctx: ctx)
                if items.isEmpty { router.say("Не нашёл операций на изображении"); return }
                router.show(.review(ReviewPayload(items: items, subtitle: "Найдено \(items.count) — проверьте перед добавлением")))
            } catch {
                router.say(error.localizedDescription)
            }
        }
    }

    var body: some View {
        HomeView()
        .id("\(sync.spaceVersion)-\(ap.version)-\(cats.version)")
        .scanFlow(isPresented: $showScan) { imgs in scan(imgs) }
        .onChange(of: router.scanRequest) { _, _ in startScan() }
        .sheet(item: $router.sheet) { route in
            switch route {
            case .voice: EmptyView()
            case .review(let p): ReviewSheet(payload: p)
            case .newTx: TxForm(tx: nil)
            case .editTx(let t): TxForm(tx: t)
            case .settings: SettingsView()
            case .stats: StatsView()
            case .payments: DebtsView()
            case .search: SearchView()
            case .insights: InsightsView()
            case .accounts: AccountsView().presentationDetents([.medium, .large])
            case .customize: CustomizeView()
            case .goals(let t): BudgetsView(tab: t)
            }
        }
        .overlay(alignment: .bottom) {
            if let t = router.toast {
                HStack(spacing: 14) {
                    Text(t)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if router.undo != nil {
                        Button { router.runUndo() } label: {
                            Text("Отменить").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(Pressable())
                    }
                }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .foregroundStyle(Color(.systemBackground))
                    .background(Theme.ink, in: Capsule())
                    .padding(.bottom, 110)
                    .transition(Motion.moves ? .move(edge: .bottom).combined(with: .opacity) : .opacity)
            }
        }
        .overlay {
            if let b = router.busy {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text(b).font(.headline).multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(40)
                }
            }
        }
        .overlay {
            if let c = router.celebrate {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    if ConfettiView.allowed { ConfettiView() }
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Theme.inc)
                            .symbolEffect(.bounce, value: c.0)
                        Text(c.0).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                        Text(c.1).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Отлично") { router.celebrate = nil }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    .padding(26)
                    .cardBG(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .padding(32)
                    .transition(Motion.moves ? .scale(scale: 0.94).combined(with: .opacity) : .opacity)
                }
                .onAppear { Haptic.success() }
            }
        }
        .animation(Motion.spring, value: router.celebrate?.0)
        .overlay {
            if router.voiceOn { VoiceOverlay() }
        }
        .animation(Motion.spring, value: router.toast)
        .onChange(of: phase) { _, p in
            if p == .active {
                if let type = SceneDelegate.pending {
                    SceneDelegate.pending = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { SceneDelegate.open(type) }
                }
                Notifier.reschedule(ctx: ctx)
                Task { await sync.sync(ctx: ctx) }
            } else if p == .background {
                ctx.commitIfNeeded()
            }
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView {
                UserDefaults.standard.set(true, forKey: "welcome.done")
                showWelcome = false
            }
            .tint(ap.accentColor)
        }
        .tint(ap.accentColor)
        .fontDesign(ap.fontDesign)
        .preferredColorScheme(ap.colorScheme)
        .task {
            if Notifier.enabled { _ = await Notifier.requestPermission() }
            Notifier.reschedule(ctx: ctx)
            // Пока приложение открыто — подтягиваем изменения семьи раз в 20 секунд
            while !Task.isCancelled {
                await sync.sync(ctx: ctx)
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }
}

extension Router {
    /// Сохраняет распознанное и показывает итог.
    func finishSave(_ res: SaveResult) {
        sheet = nil
        if let d = res.closedDebt { celebrate = ("«\(d)» закрыт!", "Долг полностью погашен. Так держать.") }
        else if let g = res.goalDone { celebrate = ("Цель «\(g)» достигнута!", "Копилка полная. Время тратить с удовольствием.") }
        else if res.summary.contains(where: { $0.contains("нет доступа") }) { say("Задачи не сохранены: разрешите доступ к Напоминаниям") }
        else { Haptic.success(); say("Добавлено: \(res.count)") }
    }
}
