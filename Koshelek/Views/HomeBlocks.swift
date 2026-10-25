import SwiftUI
import SwiftData

/// Заголовок мини-блока на главном экране.
struct BlockHeader: View {
    let title: String
    var action: String? = nil
    var onTap: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if let action, let onTap {
                Button(action: onTap) {
                    HStack(spacing: 2) { Text(action); Image(systemName: "chevron.right").font(.caption2.weight(.bold)) }
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 6)
    }
}

struct BudgetsBlock: View {
    @EnvironmentObject var router: Router
    let txs: [Tx]
    @AppStorage("budget") private var budget: Double = 0
    var body: some View {
        let limits = CatLimits.load()
        let month = txs.filter { $0.kind == .exp && $0.date.sameMonth(Date()) }
        let spent = Dictionary(grouping: month, by: { $0.cat }).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let total = month.reduce(0) { $0 + $1.amount }
        var rows: [(String, String, Color, Double, Double)] = []
        if budget > 0 { rows.append(("Все расходы", "square.stack.3d.up.fill", Theme.accent, total, budget)) }
        for (id, lim) in limits.sorted(by: { (spent[$0.key] ?? 0) / max($0.value, 1) > (spent[$1.key] ?? 0) / max($1.value, 1) }).prefix(3) {
            let c = Catalog.cat(id)
            rows.append((c.name, c.symbol, c.color, spent[id] ?? 0, lim))
        }
        return VStack(alignment: .leading, spacing: 8) {
            BlockHeader(title: "Бюджеты", action: rows.isEmpty ? "Создать" : "Все") { router.show(.goals(0)) }
            if rows.isEmpty {
                RowCard { Text("Задайте лимит — например «Кафе 8 000 ₽ в месяц»").font(.subheadline).foregroundStyle(.secondary) }
            }
            ForEach(rows.indices, id: \.self) { i in
                let r = rows[i]
                let p = r.4 > 0 ? r.3 / r.4 : 0
                RowCard {
                    CategoryTile(symbol: r.1, color: r.2, size: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.0).font(.body.weight(.medium))
                            Spacer()
                            Text(r.4 - r.3 >= 0 ? "осталось \(Fmt.rubU(r.4 - r.3))" : "перерасход \(Fmt.rubU(r.3 - r.4))")
                                .font(.footnote).foregroundStyle(r.4 - r.3 >= 0 ? Color.secondary : Theme.exp)
                        }
                        Bar(value: p, color: p > 1 ? Theme.exp : (p > 0.8 ? Theme.warn : r.2), height: 6)
                    }
                }
            }
        }
    }
}

struct GoalsBlock: View {
    @EnvironmentObject var router: Router
    @Query(sort: \Goal.created) private var qGoals: [Goal]
    private var goals: [Goal] { qGoals.live.filter { $0.target <= 0 || $0.saved < $0.target } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlockHeader(title: "Копилки · \(Fmt.rubU(Savings.totalSaved(qGoals.live)))", action: goals.isEmpty ? "Создать" : "Все") { router.show(.goals(1)) }
            if goals.isEmpty {
                RowCard { Text("Создайте копилку и включите автоправила — копить станет проще").font(.subheadline).foregroundStyle(.secondary) }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(goals.prefix(6)) { g in
                            let c = Color(hex: g.hex)
                            Button { router.show(.goals(1)) } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        CategoryTile(symbol: g.symbol, color: c, size: 36)
                                        Spacer()
                                        if g.target > 0 { Ring(value: g.saved / g.target, color: c, size: 36) }
                                    }
                                    Text(g.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(Fmt.rubU(g.saved)).font(.title3.weight(.semibold))
                                }
                                .padding(14)
                                .frame(width: 160, alignment: .leading)
                                .cardBG(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct PaymentsBlock: View {
    @EnvironmentObject var router: Router
    let debts: [Debt]
    let recs: [Recurring]
    let txs: [Tx]
    var body: some View {
        let inst = allInstallments(debts).filter { $0.isOpen && daysBetween(Date(), $0.due) <= 10 }.sorted { $0.due < $1.due }
        let now = Date()
        let upcomingRecs = recs.compactMap { r -> RecDue? in
            guard let d = r.due(in: now), d.day0 >= now.day0, daysBetween(now, d) <= 10, !r.isRecorded(in: now, txs: txs) else { return nil }
            return RecDue(rec: r, due: d)
        }
        VStack(alignment: .leading, spacing: 8) {
            BlockHeader(title: "Ближайшие платежи", action: "Все") { router.show(.payments) }
            if inst.isEmpty && upcomingRecs.isEmpty {
                RowCard { Text("На ближайшие 10 дней платежей нет").font(.subheadline).foregroundStyle(.secondary) }
            }
            ForEach(inst.prefix(3)) { x in
                Button { router.show(.payments) } label: {
                    RowCard {
                        CategoryTile(symbol: "building.columns.fill", color: x.debt.type.color, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(x.debt.name).font(.body.weight(.medium)).lineLimit(1)
                            Text(relDays(x.due).text).font(.footnote).foregroundStyle(x.st == .overdue ? Theme.exp : Color.secondary)
                        }
                        Spacer()
                        Text(Fmt.rubU(x.amount)).font(.body.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(upcomingRecs.prefix(3))) { item in
                let r = item.rec, d = item.due
                let c = Catalog.cat(r.cat)
                RowCard {
                    CategoryTile(symbol: c.symbol, color: c.color, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.body.weight(.medium)).lineLimit(1)
                        Text(relDays(d).text).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.rubU(r.amount)).font(.body.weight(.semibold))
                }
            }
        }
    }
}

struct RecDue: Identifiable {
    let rec: Recurring
    let due: Date
    var id: UUID { rec.uid }
}

struct CategoriesBlock: View {
    @EnvironmentObject var router: Router
    let txs: [Tx]
    var body: some View {
        let rows = byCategory(txs)
        let total = rows.reduce(0) { $0 + $1.sum }
        VStack(alignment: .leading, spacing: 10) {
            BlockHeader(title: "Куда уходят деньги", action: "Анализ") { router.show(.stats) }
            if rows.isEmpty {
                RowCard { Text("Пока нет расходов в этом месяце").font(.subheadline).foregroundStyle(.secondary) }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    GeometryReader { g in
                        HStack(spacing: 3) {
                            ForEach(rows) { r in
                                Capsule().fill(r.cat.color).frame(width: max(4, g.size.width * r.sum / max(total, 1) - 3))
                            }
                        }
                    }
                    .frame(height: 10)
                    ForEach(rows.prefix(4)) { r in
                        HStack(spacing: 10) {
                            Image(systemName: r.cat.symbol).foregroundStyle(r.cat.color).frame(width: 22)
                            Text(r.cat.name)
                            Spacer()
                            Text("\(Int((r.sum / max(total, 1) * 100).rounded()))%").foregroundStyle(.secondary)
                            Text(Fmt.rubU(r.sum)).fontWeight(.medium).frame(minWidth: 80, alignment: .trailing)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(16)
                .cardBG(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }
}

struct AccountsBlock: View {
    @EnvironmentObject var router: Router
    let accs: [Account]
    let txs: [Tx]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlockHeader(title: "Счета", action: accs.isEmpty ? "Добавить" : "Все") { router.show(.accounts) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(accs) { a in
                        Button { router.accFilter = router.accFilter == a.uid ? nil : a.uid } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                CategoryTile(symbol: "creditcard.fill", color: Color(hex: a.hex), size: 34)
                                Text(a.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Text(Fmt.rub(balance(of: a, txs: txs))).font(.headline)
                            }
                            .padding(14)
                            .frame(minWidth: 140, alignment: .leading)
                            .cardBG(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(router.accFilter == a.uid ? Theme.accent : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    if accs.isEmpty {
                        Button { router.show(.accounts) } label: {
                            Label("Карта, наличные…", systemImage: "plus").font(.subheadline.weight(.medium))
                                .padding(16).cardBG(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
