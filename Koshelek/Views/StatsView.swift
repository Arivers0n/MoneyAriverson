import SwiftUI
import SwiftData
import Charts

struct ChartPoint: Identifiable {
    let id = UUID()
    let month: String
    let kind: String
    let value: Double
}

struct StatsView: View {
    @EnvironmentObject var router: Router
    @Query(sort: \Tx.date, order: .reverse) private var txs: [Tx]
    @Query(sort: \Account.created) private var accs: [Account]
    @Query private var debts: [Debt]
    @Query private var recs: [Recurring]
    @Query private var goals: [Goal]
    @AppStorage("budget") private var budget: Double = 0

    @State private var month = Date().startOfMonth
    @State private var review = ""
    @State private var reviewing = false
    @State private var reviewErr: String?
    @State private var query = ""

    var months: [MonthTotals] { (0..<6).reversed().map { totals(for: month.addingMonths(-$0), txs) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    WalletHeader(title: "Анализ", onAdd: nil)
                    SectionSwitcher(titles: WalletView.sections, selection: $router.wallet)
                    MonthSwitcher(month: $month)
                    chartCard
                    reviewCard
                    compareCard
                    searchCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: month) { _, _ in review = ""; reviewErr = nil }
        }
    }

    // MARK: График

    private var chartCard: some View {
        let ms = months
        let pts = ms.flatMap { m -> [ChartPoint] in
            let label = DF.monthShort(m.month)
            return [ChartPoint(month: label, kind: "Доходы", value: m.inc), ChartPoint(month: label, kind: "Расходы", value: m.exp)]
        }
        let nz = ms.filter { $0.inc > 0 || $0.exp > 0 }
        let avg = nz.isEmpty ? 0 : nz.reduce(0) { $0 + $1.exp } / Double(nz.count)
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Полгода")
            Chart(pts) { p in
                BarMark(x: .value("Месяц", p.month), y: .value("Сумма", p.value))
                    .foregroundStyle(by: .value("Тип", p.kind))
                    .position(by: .value("Тип", p.kind))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale(["Доходы": Theme.inc, "Расходы": Theme.exp])
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.compact(d)) } }
                }
            }
            .frame(height: 190)
            if avg > 0 { Text("В среднем тратите \(Fmt.rubU(avg)) в месяц").font(.footnote).foregroundStyle(.secondary) }
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Месяц").gridColumnAlignment(.leading)
                    Text("Доход"); Text("Расход"); Text("Итог")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(ms.reversed()) { m in
                    GridRow {
                        Text(DF.monthShort(m.month)).fontWeight(.medium)
                        Text(Fmt.rubU(m.inc))
                        Text(Fmt.rubU(m.exp))
                        Text(Fmt.rub(m.net)).foregroundStyle(m.net >= 0 ? Theme.inc : Theme.exp)
                    }
                    .font(.subheadline)
                }
            }
        }
        .card()
    }

    // MARK: Разбор от Claude

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Разбор: \(DF.s(month, "LLLL"))", action: Keychain.hasKey ? (reviewing ? nil : (review.isEmpty ? "Разобрать" : "Ещё раз")) : nil) { runReview() }
            if reviewing {
                HStack(spacing: 10) { ProgressView(); Text("Claude думает…").foregroundStyle(.secondary) }
            } else if !review.isEmpty {
                Text(review).font(.body).textSelection(.enabled)
            } else if !Keychain.hasKey {
                Text("Добавьте ключ Claude API в настройках — и Claude разберёт месяц: где перерасход, что выросло, и даст советы с суммами.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Claude посмотрит на траты, лимит, долги и копилки за этот месяц и даст короткий разбор с советами.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let reviewErr { Text(reviewErr).font(.footnote).foregroundStyle(Theme.exp) }
        }
        .card()
    }

    private func runReview() {
        let ms = Array(months.suffix(3))
        func cats(_ m: MonthTotals) -> [String: Int] {
            var o: [String: Int] = [:]
            for c in byCategory(m.items) { o[c.cat.name] = Int(c.sum.rounded()) }
            return o
        }
        let cur = ms.last!
        var data: [String: Any] = [:]
        data["месяц"] = DF.month(month)
        data["сегодня"] = DF.iso(Date())
        if budget > 0 { data["лимит_расходов"] = budget }
        var byMonth: [[String: Any]] = []
        for m in ms {
            var o: [String: Any] = [:]
            o["месяц"] = DF.month(m.month); o["доход"] = Int(m.inc); o["расход"] = Int(m.exp); o["расходы_по_категориям"] = cats(m)
            byMonth.append(o)
        }
        data["по_месяцам"] = byMonth
        var big: [[String: Any]] = []
        for t in cur.items.filter({ $0.kind == .exp }).sorted(by: { $0.amount > $1.amount }).prefix(8) {
            big.append(["сумма": Int(t.amount), "категория": Catalog.cat(t.cat).name, "заметка": t.note, "дата": DF.iso(t.date)])
        }
        data["крупные_траты"] = big
        var ds: [[String: Any]] = []
        for d in debts where !d.isClosed {
            let overdue = d.schedule().filter { $0.st == .overdue }.count
            ds.append(["название": d.name, "вид": d.type.name, "я_должен": d.isOut, "осталось": Int(d.remaining), "платёж": Int(d.payment), "ставка": d.rate, "просрочено": overdue])
        }
        data["долги"] = ds
        var rs: [[String: Any]] = []
        for r in recs { rs.append(["название": r.name, "сумма": r.amount, "период": r.yearly ? "год" : "месяц"]) }
        data["подписки"] = rs
        var gs: [[String: Any]] = []
        for g in goals { gs.append(["цель": g.name, "накоплено": Int(g.saved), "нужно": g.target]) }
        data["копилки"] = gs
        reviewing = true; reviewErr = nil
        Task {
            defer { reviewing = false }
            do { review = try await Brain.review(data, monthTitle: DF.month(month)) }
            catch { reviewErr = error.localizedDescription }
        }
    }

    // MARK: Сравнение

    private var compareCard: some View {
        let cur = totals(for: month, txs), prev = totals(for: month.addingMonths(-1), txs)
        let a = Dictionary(uniqueKeysWithValues: byCategory(cur.items).map { ($0.cat.id, $0.sum) })
        let b = Dictionary(uniqueKeysWithValues: byCategory(prev.items).map { ($0.cat.id, $0.sum) })
        let keys = Set(a.keys).union(b.keys)
        let diffs: [CatDiff] = Array(keys.map { k in CatDiff(id: k, delta: (a[k] ?? 0) - (b[k] ?? 0), before: b[k] ?? 0) }
            .filter { abs($0.delta) >= 1 }
            .sorted { abs($0.delta) > abs($1.delta) }
            .prefix(5))
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Сравнение с прошлым месяцем")
            if diffs.isEmpty {
                Text("Пока нечего сравнивать — нужны траты за два месяца подряд.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(diffs) { d in
                    let c = Catalog.cat(d.id)
                    HStack {
                        RoundedRectangle(cornerRadius: 3).fill(c.color).frame(width: 10, height: 10)
                        Text(c.name)
                        Spacer()
                        Text(d.label)
                            .fontWeight(.semibold)
                            .foregroundStyle(d.delta > 0 ? Theme.exp : Theme.inc)
                    }
                    .font(.subheadline)
                }
                Text("\(DF.s(month, "LLLL").capitalizedFirst): \(Fmt.rubU(cur.exp)) против \(Fmt.rubU(prev.exp)) в прошлом месяце.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: Поиск и экспорт

    private func matches(_ t: Tx, q: String, num: Double?) -> Bool {
        if t.note.lowercased().contains(q) { return true }
        if Catalog.cat(t.cat).name.lowercased().contains(q) { return true }
        if let a = accs.first(where: { $0.uid == t.accID }), a.name.lowercased().contains(q) { return true }
        if let n = num, Int(n.rounded()) == Int(t.amount.rounded()) { return true }
        return false
    }

    private var searchCard: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let num = parseAmount(q)
        let res: [Tx] = q.isEmpty ? [] : txs.filter { matches($0, q: q, num: num) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Поиск по операциям")
                if let url = CSV.exportFile(txs: txs, accounts: accs) {
                    ShareLink(item: url) { Label("CSV", systemImage: "square.and.arrow.up") }.font(.subheadline.weight(.semibold)).padding(.bottom, 8)
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Пятёрочка, такси, 1500…", text: $query).textInputAutocapitalization(.never)
            }
            .padding(10)
            .background(Theme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !q.isEmpty {
                if res.isEmpty { Text("Ничего не нашлось").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8) }
                else {
                    Text("Найдено \(res.count) · итого \(Fmt.rub(res.reduce(0) { $0 + $1.signedAmount }))").font(.footnote).foregroundStyle(.secondary)
                    TxGroupedList(txs: Array(res.prefix(60)), accounts: accs)
                }
            }
        }
        .card()
    }
}

struct CatDiff: Identifiable {
    let id: String
    let delta: Double
    let before: Double
    var label: String {
        var s = (delta > 0 ? "+" : "−") + Fmt.rubU(delta)
        if before > 0 { s += " (\(delta > 0 ? "+" : "")\(Int((delta / before * 100).rounded()))%)" } else { s += " новое" }
        return s
    }
}
