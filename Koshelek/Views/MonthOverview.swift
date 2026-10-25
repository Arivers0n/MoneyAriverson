import SwiftUI
import Charts

/// Точка накопительного графика трат.
struct CumPoint: Identifiable {
    let day: Int
    let sum: Double
    let series: String
    var id: String { "\(series)-\(day)" }
}

/// Плитка-факт в сетке: «Средние траты в день», «Самый дорогой день»…
struct StatFact: Identifiable {
    let id: String
    let symbol: String
    let color: Color
    let title: String
    let value: String
    var detail: String = ""
}

/// Обзор месяца в стиле «одна большая цифра + график + факты».
struct MonthOverview: View {
    let txs: [Tx]
    @Binding var month: Date
    @ObservedObject private var ap = Appearance.shared
    @State private var chartIn = false

    private var cur: MonthTotals { totals(for: month, txs) }
    private var prev: MonthTotals { totals(for: month.addingMonths(-1), txs) }
    private var isCurrent: Bool { month.sameMonth(Date()) }
    private var daysPassed: Int { isCurrent ? Date().dayNum : month.daysInMonth }

    var body: some View {
        let c = cur
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                MonthPill(month: $month)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(c.net >= 0 ? "Осталось за месяц" : "Ушли в минус").font(.subheadline).foregroundStyle(.secondary)
                RollingAmount(value: c.net, font: .system(size: 48, weight: .bold), masked: ap.hideAmounts)
                    .foregroundStyle(c.net >= 0 ? Color.primary : Theme.exp)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            savingsBar(c)
            chart
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(facts(c).enumerated()), id: \.element.id) { i, f in
                    FactTile(fact: f).appearIn(i)
                }
            }
        }
        .animation(Motion.spring, value: month)
    }

    // MARK: Полоса «Сохранено X% дохода»

    @ViewBuilder private func savingsBar(_ c: MonthTotals) -> some View {
        if c.inc > 0 {
            let rate = max(-1, min(1, c.net / c.inc))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(rate >= 0 ? "Сохранено \(Int((rate * 100).rounded()))% дохода" : "Потрачено больше дохода на \(Int((-rate * 100).rounded()))%")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Fmt.rubU(c.inc)).font(.footnote).foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: rate >= 0 ? [Theme.inc.opacity(0.7), Theme.inc] : [Theme.warn, Theme.exp], startPoint: .leading, endPoint: .trailing))
                            .frame(width: chartIn ? max(8, g.size.width * abs(rate)) : 8)
                    }
                }
                .frame(height: 10)
            }
            .card()
        }
    }

    // MARK: Накопительный график: этот месяц против прошлого

    private var points: [CumPoint] {
        func cum(_ m: MonthTotals, upTo: Int, name: String) -> [CumPoint] {
            var perDay = [Double](repeating: 0, count: 32)
            for t in m.items where t.kind == .exp { perDay[min(31, t.date.dayNum)] += t.amount }
            var s = 0.0
            return (1...upTo).map { d in s += perDay[d]; return CumPoint(day: d, sum: s, series: name) }
        }
        let p = prev
        return cum(p, upTo: p.month.daysInMonth, name: "Прошлый") + cum(cur, upTo: max(1, daysPassed), name: "Этот")
    }

    private var chart: some View {
        let pts = points
        let thisTotal = pts.last { $0.series == "Этот" }?.sum ?? 0
        let prevSame = pts.first { $0.series == "Прошлый" && $0.day == daysPassed }?.sum ?? 0
        let diff = thisTotal - prevSame
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Траты по дням").font(.subheadline.weight(.semibold))
                    if prevSame > 0 {
                        Text(diff <= 0 ? "На \(Fmt.rubU(diff)) меньше, чем к этому дню в прошлом месяце" : "На \(Fmt.rubU(diff)) больше, чем к этому дню в прошлом месяце")
                            .font(.footnote).foregroundStyle(diff <= 0 ? Theme.inc : Theme.warn)
                    }
                }
                Spacer()
            }
            Chart(pts) { p in
                if p.series == "Этот" {
                    AreaMark(x: .value("День", p.day), y: .value("Сумма", chartIn ? p.sum : 0))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                }
                LineMark(x: .value("День", p.day), y: .value("Сумма", chartIn ? p.sum : 0), series: .value("Месяц", p.series))
                    .foregroundStyle(p.series == "Этот" ? Theme.accent : Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: p.series == "Этот" ? 3 : 2, lineCap: .round, dash: p.series == "Этот" ? [] : [4, 4]))
                    .interpolationMethod(.monotone)
            }
            .chartLegend(.hidden)
            .chartXScale(domain: 1...31)
            .chartXAxis { AxisMarks(values: [1, 10, 20, 31]) { _ in AxisValueLabel() } }
            .chartYAxis { AxisMarks(position: .trailing) { v in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel { if let d = v.as(Double.self) { Text(short(d)) } }
            } }
            .frame(height: 170)
            HStack(spacing: 14) {
                legend(color: Theme.accent, text: "Этот месяц", dashed: false)
                legend(color: .secondary, text: "Прошлый", dashed: true)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .card()
        .onAppear {
            guard !chartIn else { return }
            if Motion.enabled { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { chartIn = true } } else { chartIn = true }
        }
    }

    private func legend(color: Color, text: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color.opacity(dashed ? 0.5 : 1)).frame(width: 14, height: 3)
            Text(text)
        }
    }

    private func short(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fм", v / 1_000_000) }
        if v >= 1000 { return "\(Int(v / 1000))к" }
        return "\(Int(v))"
    }

    // MARK: Факты

    private func facts(_ c: MonthTotals) -> [StatFact] {
        var out: [StatFact] = []
        let exps = c.items.filter { $0.kind == .exp }
        let incs = c.items.filter { $0.kind == .inc }
        let days = max(1, daysPassed)
        out.append(StatFact(id: "avg", symbol: "calendar", color: Theme.accent, title: "Средние траты в день",
                            value: Fmt.rubU(c.exp / Double(days)),
                            detail: prev.exp > 0 ? "в прошлом: \(Fmt.rubU(prev.exp / Double(prev.month.daysInMonth)))" : ""))
        if let b = exps.max(by: { $0.amount < $1.amount }) {
            out.append(StatFact(id: "bigE", symbol: "flame", color: Theme.warn, title: "Самая большая трата",
                                value: Fmt.rubU(b.amount), detail: b.note.isEmpty ? Catalog.cat(b.cat).name : b.note))
        }
        if let b = incs.max(by: { $0.amount < $1.amount }) {
            out.append(StatFact(id: "bigI", symbol: "arrow.down.circle", color: Theme.inc, title: "Самый большой доход",
                                value: Fmt.rubU(b.amount), detail: b.note.isEmpty ? Catalog.cat(b.cat).name : b.note))
        }
        var byDay: [Int: Double] = [:]
        for t in exps { byDay[t.date.dayNum, default: 0] += t.amount }
        if let d = byDay.max(by: { $0.value < $1.value }) {
            let date = cal.date(bySetting: .day, value: d.key, of: month) ?? month
            out.append(StatFact(id: "day", symbol: "calendar.badge.exclamationmark", color: Theme.exp, title: "Самый дорогой день",
                                value: Fmt.rubU(d.value), detail: DF.s(date, "d MMMM, EEEE")))
        }
        let noSpend = (1...days).filter { byDay[$0] == nil }.count
        out.append(StatFact(id: "zero", symbol: "leaf", color: Theme.inc, title: "Дней без трат",
                            value: "\(noSpend) из \(days)", detail: noSpend == 0 ? "попробуйте день-ноль" : "так держать"))
        if let top = byCategory(c.items).first, c.exp > 0 {
            out.append(StatFact(id: "top", symbol: top.cat.symbol, color: top.cat.color, title: "Больше всего на",
                                value: top.cat.name, detail: "\(Fmt.rubU(top.sum)) · \(Int((top.sum / c.exp * 100).rounded()))%"))
        }
        if isCurrent && c.exp > 0 {
            let forecast = c.exp / Double(days) * Double(month.daysInMonth)
            out.append(StatFact(id: "fc", symbol: "chart.line.uptrend.xyaxis", color: .purple, title: "Прогноз трат",
                                value: Fmt.rubU(forecast), detail: "если темп сохранится"))
        }
        out.append(StatFact(id: "cnt", symbol: "number", color: .teal, title: "Операций",
                            value: "\(c.items.count)", detail: exps.isEmpty ? "" : "средний чек \(Fmt.rubU(c.exp / Double(exps.count)))"))
        if ap.hideAmounts {
            out = out.map { f in
                var g = f
                if f.id != "zero" && f.id != "top" && f.id != "cnt" { g = StatFact(id: f.id, symbol: f.symbol, color: f.color, title: f.title, value: "•••", detail: f.id == "bigE" || f.id == "bigI" || f.id == "day" ? f.detail : "") }
                return g
            }
        }
        return out
    }
}

struct FactTile: View {
    let fact: StatFact
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: fact.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(fact.color)
                .frame(width: 32, height: 32)
                .background(fact.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(fact.title).font(.footnote).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(fact.value).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if !fact.detail.isEmpty {
                Text(fact.detail).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .padding(14)
        .cardBG(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
