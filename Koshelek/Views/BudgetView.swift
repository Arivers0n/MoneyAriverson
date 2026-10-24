import SwiftUI
import SwiftData

struct BudgetView: View {
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Tx.date, order: .reverse) private var txs: [Tx]
    @Query(sort: \Account.created) private var accs: [Account]
    @Query private var recs: [Recurring]
    @Query private var debts: [Debt]
    @AppStorage("budget") private var budget: Double = 0

    @State private var month = Date().startOfMonth
    @State private var catFilter: String?
    @State private var showScan = false
    @State private var showBudget = false
    @State private var accEdit: AccountEditTarget?

    var monthTxs: [Tx] { txs.filter { $0.date.sameMonth(month) } }
    var shownTxs: [Tx] { catFilter.map { c in monthTxs.filter { $0.cat == c } } ?? monthTxs }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    SectionSwitcher(titles: WalletView.sections, selection: $router.wallet)
                    hero
                    alerts
                    if !byCategory(monthTxs).isEmpty { categoryStrip }
                    accountsStrip
                    operations
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { VoiceDock(onScan: startScan, onAdd: { router.show(.newTx) }) }
            .scanFlow(isPresented: $showScan) { imgs in scan(imgs) }
            .onChange(of: month) { _, _ in catFilter = nil }
            .sheet(isPresented: $showBudget) { BudgetLimitSheet(budget: $budget) }
            .sheet(item: $accEdit) { t in AccountForm(account: t.account) }
        }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 4) {
            Button { withAnimation { month = month.addingMonths(-1) } } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold)).frame(width: 30, height: 30)
            }
            Text(DF.month(month)).font(.headline).contentTransition(.opacity)
            Button { withAnimation { month = month.addingMonths(1) } } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).frame(width: 30, height: 30)
            }
            .opacity(month.sameMonth(Date()) ? 0.3 : 1)
            Spacer()
            Button { router.show(.settings) } label: {
                Image(systemName: "gearshape").font(.title3).frame(width: 36, height: 36)
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: Главная цифра

    private var hero: some View {
        let t = totals(for: month, txs)
        return VStack(alignment: .leading, spacing: 8) {
            Text(month.sameMonth(Date()) ? "Потрачено в этом месяце" : "Потрачено за \(DF.s(month, "LLLL"))")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(Fmt.rubU(t.exp))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: t.exp)
            HStack(spacing: 16) {
                Label("+" + Fmt.rubU(t.inc), systemImage: "arrow.down.left")
                    .foregroundStyle(Theme.inc)
                Label(Fmt.rub(t.net), systemImage: "equal")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .labelStyle(TightLabel())

            if budget > 0 {
                let p = t.exp / budget, left = budget - t.exp
                Button { showBudget = true } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Bar(value: p, color: p > 1 ? Theme.exp : (p > 0.8 ? Theme.warn : Theme.ink), height: 6)
                        Text(limitText(left: left)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            } else {
                Button("Задать лимит на месяц") { showBudget = true }
                    .font(.footnote.weight(.medium))
                    .padding(.top, 2)
            }
        }
    }

    private func limitText(left: Double) -> String {
        var s = left >= 0 ? "Осталось \(Fmt.rubU(left)) из \(Fmt.rubU(budget))" : "Перерасход \(Fmt.rubU(-left))"
        if month.sameMonth(Date()) && left > 0 {
            let daysLeft = month.daysInMonth - Date().dayNum + 1
            s += " · ≈\(Fmt.rubU(left / Double(max(1, daysLeft)))) в день"
        }
        return s
    }

    // MARK: Напоминания

    @ViewBuilder private var alerts: some View {
        let pend = pendingRecurring(recs, txs: txs)
        let soon = allInstallments(debts).filter { $0.debt.isOut && ($0.st == .overdue || ($0.st == .due && daysBetween(Date(), $0.due) <= 5)) }
            .sorted { $0.due < $1.due }
        if !pend.isEmpty || !soon.isEmpty {
            VStack(spacing: 0) {
                if !pend.isEmpty {
                    QuietAlert(color: Theme.accent,
                               text: pend.count == 1 ? "Записать «\(pend[0].name)» · \(Fmt.rubU(pend[0].amount))" : "\(pend.count) регулярных платежа ждут записи",
                               action: "Записать") { recordRecurring(pend) }
                }
                if !pend.isEmpty && !soon.isEmpty { Divider().padding(.leading, 22) }
                if let x = soon.first {
                    QuietAlert(color: x.st == .overdue ? Theme.exp : Theme.warn,
                               text: "\(x.debt.name) · \(Fmt.rubU(x.amount)) · \(relDays(x.due).text)",
                               action: "Открыть") { router.wallet = 1 }
                }
            }
        }
    }

    private func recordRecurring(_ pend: [Recurring]) {
        let items = pend.map { r in
            ParsedItem(type: r.kind == .inc ? .inc : .exp, cat: r.cat, amount: r.amount, amountText: Fmt.input(r.amount),
                       date: r.due(in: Date()) ?? Date().noon, note: r.name, recID: r.uid)
        }
        router.show(.review(ReviewPayload(items: items, subtitle: "Регулярные платежи этого месяца")))
    }

    // MARK: Категории

    private var categoryStrip: some View {
        let rows = byCategory(monthTxs)
        let total = rows.reduce(0) { $0 + $1.sum }
        return VStack(alignment: .leading, spacing: 12) {
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(rows) { r in
                        Capsule().fill(r.cat.color)
                            .frame(width: max(3, g.size.width * r.sum / max(total, 1) - 2))
                            .opacity(catFilter == nil || catFilter == r.cat.id ? 1 : 0.25)
                    }
                }
            }
            .frame(height: 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(rows) { r in
                        let on = catFilter == r.cat.id
                        Button { withAnimation(.snappy) { catFilter = on ? nil : r.cat.id } } label: {
                            HStack(spacing: 6) {
                                Circle().fill(r.cat.color).frame(width: 8, height: 8)
                                Text(r.cat.name).foregroundStyle(on ? Color(.systemBackground) : .primary)
                                Text(Fmt.compact(r.sum)).foregroundStyle(on ? Color(.systemBackground).opacity(0.7) : .secondary)
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(on ? Theme.ink : Theme.soft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Счета

    private var accountsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(accs) { a in
                    Button { accEdit = AccountEditTarget(account: a) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "creditcard").foregroundStyle(Color(hex: a.hex))
                            Text(a.name).foregroundStyle(.secondary)
                            Text(Fmt.rub(balance(of: a, txs: txs))).fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                }
                Button { accEdit = AccountEditTarget(account: nil) } label: {
                    Label(accs.isEmpty ? "Добавить счёт" : "Счёт", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Операции

    @ViewBuilder private var operations: some View {
        if monthTxs.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 72, height: 72)
                    .background(Theme.accent.opacity(0.1), in: Circle())
                Text(txs.isEmpty ? "Скажите, что купили" : "В этом месяце пусто").font(.title3.weight(.semibold))
                Text("Нажмите на микрофон внизу и говорите как обычно. Или удерживайте его — и отпустите, когда закончите.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else {
            TxGroupedList(txs: shownTxs, accounts: accs)
        }
    }

    // MARK: Скан

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
}

// MARK: - Док с микрофоном

struct VoiceDock: View {
    @EnvironmentObject var router: Router
    let onScan: () -> Void
    let onAdd: () -> Void
    @State private var pressStart: Date?
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 22) {
            DockButton(symbol: "camera", label: "Скан чека", action: onScan)
            ZStack {
                Circle().fill(Theme.accent).frame(width: 68, height: 68)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 5)
                Image(systemName: "mic.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.onAccent)
            }
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.15), value: pressed)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if pressStart == nil {
                            pressStart = Date(); pressed = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            router.startVoice()
                        }
                    }
                    .onEnded { _ in
                        if let s = pressStart, Date().timeIntervalSince(s) > 0.45 { router.voiceRelease += 1 }
                        pressStart = nil; pressed = false
                    }
            )
            .accessibilityLabel("Голосовой ввод")
            .accessibilityAddTraits(.isButton)
            DockButton(symbol: "plus", label: "Вручную", action: onAdd)
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }
}

struct DockButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 50, height: 50)
                .background(Theme.soft, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Мелкие элементы

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.font(.caption.weight(.bold)); configuration.title }
    }
}

struct QuietAlert: View {
    let color: Color
    let text: String
    let action: String
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(text).font(.subheadline).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                Spacer()
                Text(action).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

struct AccountEditTarget: Identifiable {
    let id = UUID()
    let account: Account?
}

struct MonthSwitcher: View {
    @Binding var month: Date
    var body: some View {
        HStack {
            Button { month = month.addingMonths(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
            Spacer()
            Text(DF.month(month)).font(.headline)
            Spacer()
            Button { month = month.addingMonths(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
        }
        .padding(4)
        .background(Theme.card, in: Capsule())
    }
}

struct TxGroupedList: View {
    @EnvironmentObject var router: Router
    let txs: [Tx]
    let accounts: [Account]

    struct DayGroup: Identifiable {
        let day: Date
        let items: [Tx]
        var id: Date { day }
    }
    var groups: [DayGroup] {
        let d = Dictionary(grouping: txs) { $0.date.day0 }
        return d.keys.sorted(by: >).map { k in DayGroup(day: k, items: (d[k] ?? []).sorted { $0.created > $1.created }) }
    }
    func accName(_ id: UUID?) -> String { accounts.first { $0.uid == id }?.name ?? "" }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { g in
                HStack {
                    Text(dayLabel(g.day))
                    Spacer()
                    Text(Fmt.signed(g.items.reduce(0) { $0 + $1.signedAmount }))
                }
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.top, 14).padding(.bottom, 4)
                ForEach(g.items) { t in
                    Button { router.show(.editTx(t)) } label: { row(t) }.buttonStyle(.plain)
                }
            }
        }
    }

    func dayLabel(_ d: Date) -> String {
        let n = daysBetween(d, Date())
        if n == 0 { return "Сегодня" }
        if n == 1 { return "Вчера" }
        return DF.s(d, "d MMMM, EEEE")
    }

    @ViewBuilder func row(_ t: Tx) -> some View {
        HStack(spacing: 14) {
            if t.kind == .tr {
                SoftIcon(symbol: "arrow.left.arrow.right", color: .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Перевод").font(.body)
                    Text("\(accName(t.accID)) → \(accName(t.toID))").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(Fmt.rubU(t.amount)).font(.body.weight(.medium)).foregroundStyle(.secondary)
            } else {
                let c = Catalog.cat(t.cat)
                SoftIcon(symbol: c.symbol, color: c.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.note.isEmpty ? c.name : t.note).font(.body).lineLimit(1)
                    let sub = [t.note.isEmpty ? "" : c.name, accounts.count > 1 ? accName(t.accID) : ""].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty { Text(sub).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                Text((t.kind == .inc ? "+" : "−") + Fmt.rubU(t.amount))
                    .font(.body.weight(.medium))
                    .foregroundStyle(t.kind == .inc ? Theme.inc : Color.primary)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

struct SoftIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: Circle())
    }
}

struct BudgetLimitSheet: View {
    @Binding var budget: Double
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(text: $text)
                } footer: { Text("Оставьте пустым, чтобы убрать лимит.") }
            }
            .navigationTitle("Лимит на месяц")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { budget = max(0, parseAmount(text) ?? 0); dismiss() }
                }
            }
            .onAppear { text = Fmt.input(budget) }
        }
        .presentationDetents([.medium])
    }
}
