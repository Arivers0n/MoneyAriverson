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
    @State private var showScan = false
    @State private var showBudget = false
    @State private var accEdit: AccountEditTarget?

    var monthTxs: [Tx] { txs.filter { $0.date.sameMonth(month) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    MonthSwitcher(month: $month)
                    actions
                    alerts
                    hero
                    accounts
                    budgetCard
                    categories
                    operations
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .navigationTitle("Кошелёк")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.show(.settings) } label: { Image(systemName: "gearshape") }
                }
            }
            .scanFlow(isPresented: $showScan) { imgs in scan(imgs) }
            .onChange(of: router.scanRequest) { _, _ in startScan() }
            .sheet(isPresented: $showBudget) { BudgetLimitSheet(budget: $budget) }
            .sheet(item: $accEdit) { t in AccountForm(account: t.account) }
        }
    }

    // MARK: Кнопки быстрого ввода

    private var actions: some View {
        HStack(spacing: 10) {
            ActionTile(title: "Голосом", sub: "просто скажите", symbol: "mic.fill", color: Theme.accent) {
                router.show(.voice(auto: true))
            }
            ActionTile(title: "Скан чека", sub: "фото, скриншот", symbol: "camera.fill", color: Theme.inc) { startScan() }
            ActionTile(title: "Вручную", sub: "форма", symbol: "plus", color: Theme.ink) { router.show(.newTx) }
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

    // MARK: Уведомления

    @ViewBuilder private var alerts: some View {
        let pend = pendingRecurring(recs, txs: txs)
        if !pend.isEmpty {
            AlertRow(color: Theme.accent, text: pend.count == 1 ? "Пора записать «\(pend[0].name)» — \(Fmt.rubU(pend[0].amount))" :
                        "\(pend.count) регулярных платежа ждут записи · \(Fmt.rubU(pend.reduce(0) { $0 + $1.amount }))",
                     button: "Записать") {
                let items = pend.map { r in
                    ParsedItem(type: r.kind == .inc ? .inc : .exp, cat: r.cat, amount: r.amount, amountText: Fmt.input(r.amount),
                               date: r.due(in: Date()) ?? Date().noon, note: r.name, recID: r.uid)
                }
                router.show(.review(ReviewPayload(items: items, subtitle: "Регулярные платежи этого месяца")))
            }
        }
        let soon = allInstallments(debts).filter { $0.debt.isOut && ($0.st == .overdue || ($0.st == .due && daysBetween(Date(), $0.due) <= 5)) }
            .sorted { $0.due < $1.due }
        if let x = soon.first {
            AlertRow(color: x.st == .overdue ? Theme.exp : Theme.warn,
                     text: "\(x.debt.name): платёж \(Fmt.rubU(x.amount)) \(relDays(x.due).text)" + (soon.count > 1 ? " · ещё \(soon.count - 1)" : ""),
                     button: "Открыть") { router.tab = 1 }
        }
    }

    // MARK: Итог месяца

    private var hero: some View {
        let t = totals(for: month, txs)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ОСТАТОК ЗА МЕСЯЦ").font(.caption.weight(.semibold)).tracking(0.8).opacity(0.8)
                Text(Fmt.rub(t.net)).font(.system(size: 38, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
            }
            HStack(spacing: 10) {
                HeroFlow(title: "Доходы", value: "+" + Fmt.rubU(t.inc))
                HeroFlow(title: "Расходы", value: "−" + Fmt.rubU(t.exp))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.onAccent)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Счета

    private var accounts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(accs) { a in
                    Button { accEdit = AccountEditTarget(account: a) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 3).fill(Color(hex: a.hex)).frame(width: 9, height: 9)
                                Text(a.name).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text(Fmt.rub(balance(of: a, txs: txs))).font(.headline)
                        }
                        .padding(12)
                        .frame(minWidth: 136, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button { accEdit = AccountEditTarget(account: nil) } label: {
                    VStack(spacing: 2) {
                        Text(accs.isEmpty ? "+ Добавить счёт" : "+ Счёт").font(.subheadline.weight(.semibold))
                        if accs.isEmpty { Text("карта, наличные").font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(12)
                    .frame(minWidth: 112, minHeight: 64)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])).foregroundStyle(.secondary.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Лимит

    private var budgetCard: some View {
        let exp = totals(for: month, txs).exp
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Лимит расходов", action: budget > 0 ? "Изменить" : "Задать") { showBudget = true }
            if budget <= 0 {
                Text("Задайте лимит, и приложение покажет, сколько ещё можно потратить в этом месяце.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                let p = exp / budget, left = budget - exp
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.rubU(exp)).font(.headline)
                    Spacer()
                    Text("из \(Fmt.rubU(budget))").foregroundStyle(.secondary)
                }
                Bar(value: p, color: p > 1 ? Theme.exp : (p > 0.8 ? Theme.warn : Theme.inc))
                Text(budgetNote(left: left)).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func budgetNote(left: Double) -> String {
        var s = left >= 0 ? "Осталось \(Fmt.rubU(left))" : "Перерасход \(Fmt.rubU(-left))"
        if month.sameMonth(Date()) && left > 0 {
            let daysLeft = month.daysInMonth - Date().dayNum + 1
            s += " · примерно \(Fmt.rubU(left / Double(max(1, daysLeft)))) в день до конца месяца"
        }
        return s
    }

    // MARK: Категории

    private var categories: some View {
        let rows = byCategory(monthTxs)
        let total = rows.reduce(0) { $0 + $1.sum }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Куда ушли деньги")
            if rows.isEmpty {
                Text("Расходов за этот месяц пока нет.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                GeometryReader { g in
                    HStack(spacing: 0) {
                        ForEach(rows) { r in
                            Rectangle().fill(r.cat.color).frame(width: g.size.width * r.sum / total)
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())
                ForEach(rows) { r in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(r.cat.color).frame(width: 10, height: 10)
                        Text(r.cat.name).lineLimit(1)
                        Spacer()
                        Text("\(Int((r.sum / total * 100).rounded()))%").font(.footnote).foregroundStyle(.secondary)
                        Text(Fmt.rubU(r.sum)).fontWeight(.semibold).frame(minWidth: 84, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            }
        }
        .card()
    }

    // MARK: Операции

    private var operations: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: "Операции")
            if monthTxs.isEmpty {
                EmptyNote(title: txs.isEmpty ? "Здесь появятся ваши операции" : "В этом месяце пусто",
                          text: "Нажмите «Голосом» и скажите, например: «продукты тысяча двести».")
            } else {
                TxGroupedList(txs: monthTxs, accounts: accs)
            }
        }
        .card()
    }
}

struct AccountEditTarget: Identifiable {
    let id = UUID()
    let account: Account?
}

struct ActionTile: View {
    let title: String
    let sub: String
    let symbol: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color == Theme.ink ? Color(.systemBackground) : .white)
                    .frame(width: 48, height: 48)
                    .background(color, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Text(title).font(.subheadline.weight(.semibold))
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AlertRow: View {
    let color: Color
    let text: String
    let button: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Button(button, action: action).font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct HeroFlow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).opacity(0.8)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
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
        VStack(spacing: 0) {
            ForEach(groups) { g in
                HStack {
                    Text(dayLabel(g.day).uppercased())
                    Spacer()
                    Text(Fmt.signed(g.items.reduce(0) { $0 + $1.signedAmount }))
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.top, 12).padding(.bottom, 4)
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
        return DF.s(d, "d MMMM, EE")
    }

    @ViewBuilder func row(_ t: Tx) -> some View {
        HStack(spacing: 12) {
            if t.kind == .tr {
                IconBadge(symbol: "arrow.left.arrow.right", color: .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Перевод").font(.body.weight(.medium))
                    Text("\(accName(t.accID)) → \(accName(t.toID))").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(Fmt.rubU(t.amount)).fontWeight(.semibold).foregroundStyle(.secondary)
            } else {
                let c = Catalog.cat(t.cat)
                IconBadge(symbol: c.symbol, color: c.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.body.weight(.medium)).lineLimit(1)
                    let sub = [t.note, accounts.count > 1 ? accName(t.accID) : ""].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty { Text(sub).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                Text((t.kind == .inc ? "+" : "−") + Fmt.rubU(t.amount))
                    .fontWeight(.semibold)
                    .foregroundStyle(t.kind == .inc ? Theme.inc : Color.primary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
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
