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

    var body: some View {
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("Сегодня", systemImage: "sun.max.fill") }
                .tag(0)
            WalletView()
                .tabItem { Label("Кошелёк", systemImage: "creditcard.fill") }
                .badge(overdueCount + pendingCount)
                .tag(1)
            LifeView()
                .tabItem { Label("Дела", systemImage: "checklist") }
                .tag(2)
            CardsView()
                .tabItem { Label("Карты", systemImage: "wallet.pass.fill") }
                .tag(3)
        }
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
