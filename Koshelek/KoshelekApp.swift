import SwiftUI
import SwiftData

@main
struct KoshelekApp: App {
    @StateObject private var router = Router.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .onOpenURL { router.handle(url: $0) }
                .tint(Theme.accent)
        }
        .modelContainer(Store.container)
    }
}

struct RootView: View {
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var phase
    @Query private var debts: [Debt]
    @Query private var txs: [Tx]
    @Query private var recs: [Recurring]

    var overdueCount: Int { allInstallments(debts).filter { $0.st == .overdue && $0.debt.isOut }.count }
    var pendingCount: Int { pendingRecurring(recs, txs: txs).count }

    @State private var showScan = false

    /// Выбор вкладки «Голос» не переключает экран, а открывает голосовую панель.
    private var tabSelection: Binding<Int> {
        Binding(get: { router.tab }, set: { v in
            if v == 4 { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); router.startVoice() }
            else { router.tab = v }
        })
    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: tabSelection) {
                Tab("Сегодня", systemImage: "sun.max.fill", value: 0) { TodayView() }
                Tab("Кошелёк", systemImage: "creditcard.fill", value: 1) { WalletView() }
                    .badge(overdueCount + pendingCount)
                Tab("Дела", systemImage: "checklist", value: 2) { LifeView() }
                Tab("Карты", systemImage: "wallet.pass.fill", value: 3) { CardsView() }
                Tab("Сказать", systemImage: "mic.fill", value: 4, role: .search) { Color.clear }
            }
        } else {
            TabView(selection: $router.tab) {
                TodayView().tabItem { Label("Сегодня", systemImage: "sun.max.fill") }.tag(0)
                WalletView().tabItem { Label("Кошелёк", systemImage: "creditcard.fill") }.badge(overdueCount + pendingCount).tag(1)
                LifeView().tabItem { Label("Дела", systemImage: "checklist") }.tag(2)
                CardsView().tabItem { Label("Карты", systemImage: "wallet.pass.fill") }.tag(3)
            }
            .overlay(alignment: .bottomTrailing) {
                Button { router.startVoice() } label: {
                    Image(systemName: "mic.fill").font(.title3.weight(.semibold)).foregroundStyle(Theme.onAccent)
                        .frame(width: 56, height: 56).background(Theme.accent, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                }
                .padding(.trailing, 18).padding(.bottom, 64)
            }
        }
    }

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
        tabs
        .scanFlow(isPresented: $showScan) { imgs in scan(imgs) }
        .onChange(of: router.scanRequest) { _, _ in startScan() }
        .sheet(item: $router.sheet) { route in
            switch route {
            case .voice: EmptyView()
            case .review(let p): ReviewSheet(payload: p)
            case .newTx: TxForm(tx: nil)
            case .editTx(let t): TxForm(tx: t)
            case .settings: SettingsView()
            }
        }
        .overlay(alignment: .bottom) {
            if let t = router.toast {
                Text(t)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .foregroundStyle(Color(.systemBackground))
                    .background(Theme.ink, in: Capsule())
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                    ConfettiView()
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Theme.inc)
                        Text(c.0).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                        Text(c.1).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Отлично") { router.celebrate = nil }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    .padding(26)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .padding(32)
                }
            }
        }
        .overlay {
            if router.voiceOn { VoiceOverlay() }
        }
        .animation(.spring(duration: 0.3), value: router.toast)
        .onChange(of: phase) { _, p in
            if p == .active { Notifier.reschedule(ctx: ctx) }
        }
        .task {
            if Notifier.enabled { _ = await Notifier.requestPermission() }
            Notifier.reschedule(ctx: ctx)
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
        else { say("Добавлено: \(res.count)") }
    }
}
