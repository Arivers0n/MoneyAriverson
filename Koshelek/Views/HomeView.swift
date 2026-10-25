import SwiftUI
import SwiftData

/// Главный и единственный экран: итог месяца и лента операций. Остальное — в шторках.
struct HomeView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Tx.date, order: .reverse) private var qTxs: [Tx]
    private var allTxs: [Tx] { qTxs.live }
    @Query(sort: \Account.created) private var qAccs: [Account]
    private var accs: [Account] { qAccs.live }
    @Query private var qDebts: [Debt]
    private var debts: [Debt] { qDebts.live }
    @Query private var qRecs: [Recurring]
    private var recs: [Recurring] { qRecs.live }

    @State private var month = Date().startOfMonth
    @State private var pressStart: Date?
    @State private var micPressed = false

    /// Операции с учётом выбранного счёта.
    private var txs: [Tx] {
        guard let a = router.accFilter else { return allTxs }
        return allTxs.filter { $0.accID == a || $0.toID == a }
    }
    private var monthTxs: [Tx] { txs.filter { $0.date.sameMonth(month) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                    .padding(.top, 4)
                hero
                    .padding(.top, 34)
                attention
                    .padding(.top, 14)
                feed
                    .padding(.top, 22)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .refreshable { await sync.sync(ctx: ctx) }
        .safeAreaInset(edge: .bottom) { bottomButtons }
    }

    // MARK: Верхняя панель

    private var accountTitle: String {
        if let a = router.accFilter, let acc = accs.first(where: { $0.uid == a }) { return acc.name }
        if let s = sync.currentSpace, !s.personal { return s.name }
        return accs.isEmpty ? "Кошелёк" : "Все счета"
    }

    private var accountAmount: String {
        if let a = router.accFilter, let acc = accs.first(where: { $0.uid == a }) { return Fmt.rub(balance(of: acc, txs: allTxs)) }
        if !accs.isEmpty { return Fmt.rub(accs.reduce(0) { $0 + balance(of: $1, txs: allTxs) }) }
        return Fmt.rub(allTxs.reduce(0) { $0 + $1.signedAmount })
    }

    private var topBar: some View {
        let overdue = allInstallments(debts).contains { $0.st == .overdue && $0.debt.isOut } || !pendingRecurring(recs, txs: allTxs).isEmpty
        return HStack(spacing: 10) {
            AccountPill(title: accountTitle, amount: accountAmount) { router.show(.accounts) }
                .layoutPriority(1)
            Spacer(minLength: 0)
            GlassIconGroup(items: [
                .init(symbol: "magnifyingglass") { router.show(.search) },
                .init(symbol: "chart.pie") { router.show(.stats) },
                .init(symbol: "calendar", dot: overdue) { router.show(.payments) },
                .init(symbol: "cylinder.split.1x2") { router.show(.goals(0)) },
            ])
            GlassCircle(symbol: "gearshape") { router.show(.settings) }
        }
    }

    // MARK: Итог месяца

    private var hero: some View {
        let t = totals(for: month, txs)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Итог за").foregroundStyle(.secondary)
                MonthPill(month: $month)
                if !month.sameMonth(Date()) {
                    Button { withAnimation(.snappy) { month = Date().startOfMonth } } label: {
                        Image(systemName: "arrow.uturn.backward.circle").font(.title3).foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            Text(Fmt.rub(t.net))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4).lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: t.net)
            HStack(spacing: 22) {
                FlowChip(symbol: "arrow.down.left", color: Theme.inc, text: Fmt.rubU(t.inc), textColor: Theme.inc)
                FlowChip(symbol: "arrow.up.right", color: Theme.warn, text: Fmt.rubU(t.exp), textColor: .primary)
            }
            Button { router.show(.insights) } label: {
                Label("Инсайты", systemImage: "sparkle")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 18).frame(height: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glass(Capsule(), interactive: true)
            .padding(.top, 4)
        }
    }

    // MARK: Что требует внимания (одна строка, если есть)

    @ViewBuilder private var attention: some View {
        let soon = allInstallments(debts).filter { $0.debt.isOut && ($0.st == .overdue || ($0.st == .due && daysBetween(Date(), $0.due) <= 3)) }
            .sorted { $0.due < $1.due }
        let pend = pendingRecurring(recs, txs: allTxs)
        if let x = soon.first {
            AttentionPill(color: x.st == .overdue ? Theme.exp : Theme.warn,
                          text: "\(x.debt.name) · \(Fmt.rubU(x.amount)) · \(relDays(x.due).text)") { router.show(.payments) }
        } else if !pend.isEmpty {
            AttentionPill(color: Theme.accent,
                          text: pend.count == 1 ? "Записать «\(pend[0].name)» · \(Fmt.rubU(pend[0].amount))" : "Записать регулярные платежи · \(pend.count)") {
                let items = pend.map { r in
                    ParsedItem(type: r.kind == .inc ? .inc : .exp, cat: r.cat, amount: r.amount, amountText: Fmt.input(r.amount),
                               date: r.due(in: Date()) ?? Date().noon, note: r.name, recID: r.uid)
                }
                router.show(.review(ReviewPayload(items: items, subtitle: "Регулярные платежи этого месяца")))
            }
        }
    }

    // MARK: Лента

    @ViewBuilder private var feed: some View {
        if monthTxs.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
                Text(allTxs.isEmpty ? "Скажите, что купили" : "В этом месяце пусто").font(.headline)
                Text("Нажмите на микрофон и говорите как обычно: «кофе 250, такси 400». Или удерживайте его и отпустите, когда закончите.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20).padding(.top, 50)
        } else {
            TxGroupedList(txs: monthTxs, accounts: accs)
        }
    }

    // MARK: Три кнопки снизу

    private var bottomButtons: some View {
        HStack(spacing: 18) {
            GlassCircle(symbol: "viewfinder", size: 60) { router.scanRequest += 1 }
            ZStack {
                Image(systemName: "mic")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 78, height: 78)
                    .contentShape(Circle())
            }
            .glass(Circle(), interactive: true)
            .scaleEffect(micPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.15), value: micPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if pressStart == nil {
                            pressStart = Date(); micPressed = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            router.startVoice()
                        }
                    }
                    .onEnded { _ in
                        if let s = pressStart, Date().timeIntervalSince(s) > 0.45 { router.voiceRelease += 1 }
                        pressStart = nil; micPressed = false
                    }
            )
            .accessibilityLabel("Сказать голосом")
            .accessibilityAddTraits(.isButton)
            GlassCircle(symbol: "plus", size: 60) { router.show(.newTx) }
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
    }
}

struct FlowChip: View {
    let symbol: String
    let color: Color
    let text: String
    let textColor: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.2), in: Circle())
            Text(text).font(.title3.weight(.medium)).foregroundStyle(textColor)
                .contentTransition(.numericText())
        }
    }
}

struct AttentionPill: View {
    let color: Color
    let text: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(text).font(.footnote.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).frame(height: 34)
            .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
