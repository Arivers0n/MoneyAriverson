import SwiftUI
import SwiftData

// MARK: - Лимиты по категориям (синхронизируются вместе с настройками бюджета)

enum CatLimits {
    static var key: String { "catLimits:\(Space.current)" }
    static func load() -> [String: Double] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode([String: Double].self, from: d) else { return [:] }
        return v
    }
    @MainActor
    static func save(_ v: [String: Double]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: key)
        UserDefaults.standard.set(true, forKey: "prefsDirty:\(Space.current)")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "prefsTs:\(Space.current)")
        SyncEngine.shared.schedulePush()
    }
}

struct LimitTarget: Identifiable { let id = UUID(); let cat: String? }

// MARK: - Шторка «Бюджеты | Копилки»

struct BudgetsView: View {
    @State var tab: Int
    @Query(sort: \Tx.date, order: .reverse) private var qTxs: [Tx]
    private var txs: [Tx] { qTxs.live }
    @AppStorage("budget") private var budget: Double = 0
    @State private var limits: [String: Double] = CatLimits.load()
    @State private var edit: LimitTarget?
    @State private var addGoal = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    PillToggle(options: [
                        .init(id: 0, title: "Бюджеты", symbol: "cylinder.split.1x2"),
                        .init(id: 1, title: "Копилки", symbol: "target"),
                    ], selection: $tab)
                    HStack {
                        CloseButton()
                        Spacer()
                        GlassCircle(symbol: "plus", weight: .semibold) {
                            if tab == 0 { edit = LimitTarget(cat: nil) } else { addGoal += 1 }
                        }
                    }
                }
                if tab == 0 { budgets } else { SavingsView(addRequest: $addGoal) }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $edit) { t in
            LimitForm(cat: t.cat, limits: $limits, overall: $budget)
        }
    }

    private var monthTxs: [Tx] { txs.filter { $0.kind == .exp && $0.date.sameMonth(Date()) } }

    @ViewBuilder private var budgets: some View {
        let spentBy = Dictionary(grouping: monthTxs, by: { $0.cat }).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let totalSpent = monthTxs.reduce(0) { $0 + $1.amount }
        let cats = limits.keys.sorted { (limits[$0] ?? 0) > (limits[$1] ?? 0) }
        if budget <= 0 && cats.isEmpty {
            EmptyState(symbol: "cylinder.split.1x2", title: "Бюджетов пока нет",
                       text: "Задайте лимит на месяц — общий или на категорию, например «Кафе — 8 000 ₽». Я покажу, сколько осталось, и предупрежу заранее.")
            Button { edit = LimitTarget(cat: nil) } label: {
                Text("Создать бюджет").font(.body.weight(.semibold)).padding(.horizontal, 24).frame(height: 50).contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glass(Capsule(), interactive: true)
        } else {
            let daysLeft = Date().daysInMonth - Date().dayNum + 1
            Text("\(DF.s(Date(), "LLLL").capitalizedFirst) · осталось \(daysLeft) \(plural(daysLeft, "день", "дня", "дней"))")
                .font(.subheadline).foregroundStyle(.secondary)
            if budget > 0 {
                LimitCard(symbol: "square.stack.3d.up.fill", color: Theme.accent, title: "Все расходы",
                          spent: totalSpent, limit: budget, daysLeft: daysLeft) { edit = LimitTarget(cat: "all") }
            }
            ForEach(cats, id: \.self) { id in
                let c = Catalog.cat(id)
                LimitCard(symbol: c.symbol, color: c.color, title: c.name, spent: spentBy[id] ?? 0, limit: limits[id] ?? 0, daysLeft: daysLeft) {
                    edit = LimitTarget(cat: id)
                }
            }
        }
    }
}

struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { GlassCircle(symbol: "xmark", weight: .semibold) { dismiss() } }
}

struct LimitCard: View {
    let symbol: String
    let color: Color
    let title: String
    let spent: Double
    let limit: Double
    let daysLeft: Int
    let onTap: () -> Void
    var body: some View {
        let p = limit > 0 ? spent / limit : 0
        let left = limit - spent
        let barColor = p > 1 ? Theme.exp : (p > 0.8 ? Theme.warn : color)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    CategoryTile(symbol: symbol, color: color, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.title3.weight(.medium))
                        Text("\(Fmt.rubU(spent)) из \(Fmt.rubU(limit))").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(left >= 0 ? Fmt.rubU(left) : "−" + Fmt.rubU(-left))
                            .font(.title3.weight(.semibold)).foregroundStyle(left >= 0 ? Color.primary : Theme.exp)
                        Text(left >= 0 ? "осталось" : "перерасход").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Bar(value: p, color: barColor, height: 8)
                if left > 0 && daysLeft > 0 {
                    Text("≈ \(Fmt.rubU(left / Double(daysLeft))) в день").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct LimitForm: View {
    let cat: String?
    @Binding var limits: [String: Double]
    @Binding var overall: Double
    @Environment(\.dismiss) private var dismiss
    @State private var pick = "all"
    @State private var amount = ""

    var isNew: Bool { cat == nil }

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Section("На что") {
                        FlowLayout {
                            Chip(title: "Все расходы", color: Theme.accent, selected: pick == "all") { pick = "all"; prefill() }
                            ForEach(Catalog.expense.filter { $0.id != "savings" }) { c in
                                Chip(title: c.name, color: c.color, selected: pick == c.id) { pick = c.id; prefill() }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    AmountField(text: $amount)
                } header: { Text("Лимит на месяц") } footer: {
                    Text("Каждый месяц лимит начинается заново. Предупрежу, когда потрачено больше 80%.")
                }
                if !isNew {
                    Section { Button("Удалить бюджет", role: .destructive) { remove() } }
                }
            }
            .navigationTitle(isNew ? "Новый бюджет" : (pick == "all" ? "Все расходы" : Catalog.cat(pick).name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled((parseAmount(amount) ?? 0) <= 0) }
            }
            .onAppear {
                pick = cat ?? "all"
                prefill()
            }
        }
        .presentationDetents([.large])
    }

    private func prefill() {
        let v = pick == "all" ? overall : (limits[pick] ?? 0)
        amount = v > 0 ? Fmt.input(v) : ""
    }

    private func save() {
        let v = max(0, parseAmount(amount) ?? 0)
        if pick == "all" { overall = v; SyncEngine.shared.setBudget(v) }
        else { limits[pick] = v; CatLimits.save(limits) }
        dismiss()
    }

    private func remove() {
        if pick == "all" { overall = 0; SyncEngine.shared.setBudget(0) }
        else { limits.removeValue(forKey: pick); CatLimits.save(limits) }
        dismiss()
    }
}

// MARK: - Счета: выбор и управление

struct AccountsView: View {
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.created) private var qAccs: [Account]
    private var accs: [Account] { qAccs.live }
    @Query private var qTxs: [Tx]
    private var txs: [Tx] { qTxs.live }
    @State private var edit: AccountEditTarget?

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                SheetBar(title: "Счета", symbol: "wallet.bifold") {
                    GlassCircle(symbol: "plus", weight: .semibold) { edit = AccountEditTarget(account: nil) }
                }
                .padding(.bottom, 14)
                row(nil, title: "Все счета", amount: accs.isEmpty ? txs.reduce(0) { $0 + $1.signedAmount } : accs.reduce(0) { $0 + balance(of: $1, txs: txs) }, color: Theme.inc)
                ForEach(accs) { a in
                    row(a.uid, title: a.name, amount: balance(of: a, txs: txs), color: Color(hex: a.hex))
                        .contextMenu { Button { edit = AccountEditTarget(account: a) } label: { Label("Изменить", systemImage: "pencil") } }
                }
                if accs.isEmpty {
                    Text("Добавьте карту, наличные или накопительный счёт — баланс каждого будет считаться сам.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 20).padding(.horizontal, 20)
                } else {
                    Text("Удерживайте счёт, чтобы изменить его").font(.footnote).foregroundStyle(.tertiary).padding(.top, 8)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 30)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(item: $edit) { t in AccountForm(account: t.account) }
    }

    private func row(_ id: UUID?, title: String, amount: Double, color: Color) -> some View {
        Button {
            router.accFilter = id
            dismiss()
        } label: {
            RowCard {
                CategoryTile(symbol: id == nil ? "wallet.bifold.fill" : "creditcard.fill", color: color, size: 46)
                Text(title).font(.title3.weight(.medium))
                Spacer()
                Text(Fmt.rub(amount)).font(.title3.weight(.medium))
                if router.accFilter == id { Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(Theme.accent) }
            }
        }
        .buttonStyle(.plain)
    }
}
