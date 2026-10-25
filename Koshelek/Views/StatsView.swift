import SwiftUI
import SwiftData
import Charts

struct ChartPoint: Identifiable {
    let id = UUID()
    let month: String
    let kind: String
    let value: Double
}

// MARK: - Анализ: кольцо категорий и тренды

struct StatsView: View {
    @EnvironmentObject var router: Router
    @Query(sort: \Tx.date, order: .reverse) private var qTxs: [Tx]
    private var allTxs: [Tx] { qTxs.live }
    @Query(sort: \Account.created) private var qAccs: [Account]
    private var accs: [Account] { qAccs.live }

    @State private var month = Date().startOfMonth
    @State private var kind = 1          // 0 — приход, 1 — расход
    @State private var trends = false
    @State private var hidden: Set<String> = []
    @State private var selected: String?

    private var txs: [Tx] {
        guard let a = router.accFilter else { return allTxs }
        return allTxs.filter { $0.accID == a || $0.toID == a }
    }
    var months: [MonthTotals] { (0..<6).reversed().map { totals(for: month.addingMonths(-$0), txs) } }

    private var rows: [CatSum] {
        let k: TxKind = kind == 0 ? .inc : .exp
        var d: [String: Double] = [:]
        for t in txs where t.kind == k && t.date.sameMonth(month) { d[t.cat, default: 0] += t.amount }
        return d.map { CatSum(cat: Catalog.cat($0.key), sum: $0.value) }.sorted { $0.sum > $1.sum }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                SheetBar(title: trends ? "Тренды" : "Категории") {
                    HStack(spacing: 2) {
                        Button { withAnimation(.snappy) { trends.toggle() } } label: {
                            Image(systemName: trends ? "chart.pie" : "chart.bar.xaxis").font(.system(size: 19, weight: .medium))
                                .frame(width: 44, height: 46).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if let url = CSV.exportFile(txs: txs, accounts: accs) {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .medium))
                                    .frame(width: 44, height: 46).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
                    .glass(Capsule())
                }
                if trends {
                    MonthPill(month: $month)
                    chartCard
                    compareCard
                } else {
                    HStack(spacing: 10) {
                        PillToggle(options: [
                            .init(id: 0, title: "Приход", symbol: "arrow.down.left", color: Theme.inc),
                            .init(id: 1, title: "Расход", symbol: "arrow.up.right", color: Theme.warn),
                        ], selection: $kind)
                        MonthPill(month: $month)
                    }
                    donut
                    categoryList
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Backdrop())
        .onChange(of: kind) { _, _ in hidden = []; selected = nil }
        .onChange(of: month) { _, _ in hidden = []; selected = nil }
    }

    // MARK: Кольцо

    private var donut: some View {
        let shown = rows.filter { !hidden.contains($0.cat.id) }
        let total = shown.reduce(0) { $0 + $1.sum }
        let focus = selected.flatMap { id in shown.first { $0.cat.id == id } }
        return ZStack {
            if shown.isEmpty {
                Circle().stroke(Theme.card, lineWidth: 64).padding(32)
            } else {
                Chart(shown) { r in
                    SectorMark(angle: .value("Сумма", r.sum), innerRadius: .ratio(0.62), angularInset: 2.5)
                        .cornerRadius(8)
                        .foregroundStyle(r.cat.color.opacity(selected == nil || selected == r.cat.id ? 1 : 0.3))
                }
                .chartLegend(.hidden)
            }
            VStack(spacing: 4) {
                Text(focus?.cat.name ?? "Итого").font(.subheadline).foregroundStyle(.secondary)
                Text(Fmt.rubU(focus?.sum ?? total)).font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                if let f = focus, total > 0 {
                    Text("\(Int((f.sum / total * 100).rounded()))%").font(.subheadline.weight(.semibold)).foregroundStyle(f.cat.color)
                }
            }
        }
        .frame(height: 320)
        .animation(.snappy, value: hidden)
        .animation(.snappy, value: selected)
    }

    private var categoryList: some View {
        let all = rows
        let total = all.filter { !hidden.contains($0.cat.id) }.reduce(0) { $0 + $1.sum }
        return VStack(spacing: 8) {
            RowCard {
                Text("Все категории").font(.title3.weight(.medium))
                Spacer()
                Text(Fmt.rubU(total)).font(.title3.weight(.medium))
                CheckDot(on: hidden.isEmpty) { withAnimation { hidden = hidden.isEmpty ? Set(all.map { $0.cat.id }) : [] } }
            }
            if all.isEmpty {
                Text(kind == 0 ? "Доходов в этом месяце нет" : "Расходов в этом месяце нет")
                    .foregroundStyle(.secondary).padding(.vertical, 20)
            }
            ForEach(all) { r in
                let on = !hidden.contains(r.cat.id)
                Button { withAnimation(.snappy) { selected = selected == r.cat.id ? nil : r.cat.id } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: r.cat.symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(r.cat.color).frame(width: 28)
                        Text(r.cat.name).font(.title3.weight(.medium)).foregroundStyle(r.cat.color)
                        Spacer()
                        Text(Fmt.rubU(r.sum)).font(.title3.weight(.medium))
                        CheckDot(on: on) {
                            withAnimation(.snappy) { if on { hidden.insert(r.cat.id) } else { hidden.remove(r.cat.id) } }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(selected == r.cat.id ? r.cat.color.opacity(0.18) : Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .opacity(on ? 1 : 0.45)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Тренды

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

}

struct CheckDot: View {
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(on ? Color(.systemBackground) : Color.secondary, on ? Color.primary.opacity(0.85) : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Поиск

struct SearchView: View {
    @Query(sort: \Tx.date, order: .reverse) private var qTxs: [Tx]
    private var txs: [Tx] { qTxs.live }
    @Query(sort: \Account.created) private var qAccs: [Account]
    private var accs: [Account] { qAccs.live }
    @State private var query = ""
    @FocusState private var focused: Bool

    private func matches(_ t: Tx, q: String, num: Double?) -> Bool {
        if t.note.lowercased().contains(q) { return true }
        if Catalog.cat(t.cat).name.lowercased().contains(q) { return true }
        if let a = accs.first(where: { $0.uid == t.accID }), a.name.lowercased().contains(q) { return true }
        if let n = num, Int(n.rounded()) == Int(t.amount.rounded()) { return true }
        return false
    }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let num = parseAmount(q)
        let res: [Tx] = q.isEmpty ? [] : txs.filter { matches($0, q: q, num: num) }
        ScrollView {
            VStack(spacing: 16) {
                SheetBar(title: "Поиск", symbol: "magnifyingglass")
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Пятёрочка, такси, 1500…", text: $query)
                        .focused($focused)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    }
                }
                .font(.title3)
                .padding(.horizontal, 16).frame(height: 54)
                .cardBG(Capsule())
                if q.isEmpty {
                    Text("Ищите по заметке, категории, счёту или сумме").foregroundStyle(.secondary).padding(.top, 30)
                } else if res.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "Ничего не нашлось", text: "Попробуйте другое слово или точную сумму.")
                } else {
                    HStack {
                        Text("Найдено \(res.count)")
                        Spacer()
                        Text("итого \(Fmt.rub(res.reduce(0) { $0 + $1.signedAmount }))")
                    }
                    .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 10)
                    TxGroupedList(txs: Array(res.prefix(100)), accounts: accs)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Backdrop())
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true } }
    }
}

// MARK: - Инсайты: подсказки, совет дня, разбор месяца, чат

struct InsightsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Tx.date, order: .reverse) private var qTxs: [Tx]
    private var txs: [Tx] { qTxs.live }
    @Query private var qDebts: [Debt]
    private var debts: [Debt] { qDebts.live }
    @Query private var qRecs: [Recurring]
    private var recs: [Recurring] { qRecs.live }
    @Query private var qGoals: [Goal]
    private var goals: [Goal] { qGoals.live }
    @AppStorage("budget") private var budget: Double = 0

    @State private var month = Date().startOfMonth
    @State private var tip: String? = Advisor.cachedTip()
    @State private var tipLoading = false
    @State private var review = ""
    @State private var reviewing = false
    @State private var reviewErr: String?
    @State private var showChat = false

    var months: [MonthTotals] { (0..<6).reversed().map { totals(for: month.addingMonths(-$0), txs) } }

    var body: some View {
        let list = Advisor.insights(txs: txs, debts: debts, recs: recs, budget: budget)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetBar(title: "Инсайты", symbol: "sparkle")
                    .padding(.bottom, 8)
                if Keychain.hasKey {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Совет дня", systemImage: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                        if let tip { Text(tip).font(.body) }
                        else if tipLoading { HStack { ProgressView(); Text("Смотрю на ваши цифры…").foregroundStyle(.secondary) } }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                ForEach(list) { i in
                    RowCard {
                        CategoryTile(symbol: i.symbol, color: i.color, size: 42)
                        Text(i.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if list.isEmpty && !Keychain.hasKey {
                    EmptyState(symbol: "sparkle", title: "Пока всё спокойно", text: "Записывайте траты — и здесь появятся подсказки. С ключом Claude API будет ещё совет дня и разбор месяца.")
                }
                Button { showChat = true } label: {
                    Label("Спросить советника", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 52)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glass(Capsule(), interactive: true)
                .padding(.top, 6)
                reviewCard
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Backdrop())
        .sheet(isPresented: $showChat) { AdvisorChat() }
        .task {
            guard tip == nil, Keychain.hasKey else { return }
            tipLoading = true
            tip = try? await Advisor.dailyTip(ctx: ctx)
            tipLoading = false
        }
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Разбор месяца", action: Keychain.hasKey ? (reviewing ? nil : (review.isEmpty ? "Разобрать" : "Ещё раз")) : nil) { runReview() }
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
