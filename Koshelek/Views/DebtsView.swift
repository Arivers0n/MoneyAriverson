import SwiftUI
import SwiftData

struct PayTarget: Identifiable {
    let id = UUID()
    let debt: Debt
    let index: Int   // -1 = досрочный
}

struct DebtsView: View {
    @EnvironmentObject var router: Router
    @Query(sort: \Debt.created) private var qDebts: [Debt]
    private var debts: [Debt] { qDebts.live }
    @Query private var qTxs: [Tx]
    private var txs: [Tx] { qTxs.live }
    @State private var calMonth = Date().startOfMonth
    @State private var selDay: Date?
    @State private var showForm = false
    @State private var pay: PayTarget?

    var outOpen: [Debt] { debts.filter { $0.isOut && !$0.isClosed } }
    var inOpen: [Debt] { debts.filter { !$0.isOut && !$0.isClosed } }
    var closed: [Debt] { debts.filter { $0.isClosed } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    WalletHeader(title: "Платежи") { showForm = true }
                    hero
                    overdueAlert
                    if !debts.isEmpty { tiles }
                    calendar
                    RecurringCard()
                    lists
                    advice
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let d = debts.first(where: { $0.uid == id }) { DebtDetail(debt: d) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showForm = true } label: { Label("Добавить", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showForm) { DebtForm(debt: nil) }
            .sheet(item: $pay) { p in PaySheet(debt: p.debt, index: p.index) }
        }
    }

    // MARK: Шапка

    @ViewBuilder private var hero: some View {
        if debts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("КРЕДИТЫ И ДОЛГИ").font(.caption.weight(.semibold)).tracking(0.8).opacity(0.75)
                Text("Добавьте кредит, кредитку, микрозайм или долг знакомому. Приложение построит график, напомнит о платежах и посчитает, когда вы станете свободны от долгов.")
                    .opacity(0.9)
                Button { showForm = true } label: {
                    Label("Добавить долг", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).tint(Color(.systemBackground)).foregroundStyle(Theme.ink)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color(.systemBackground))
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            let totalRem = outOpen.reduce(0) { $0 + $1.remaining }
            let paidAll = debts.filter { $0.isOut }.reduce(0) { $0 + $1.paidSum }
            let next = allInstallments(debts).filter { $0.debt.isOut && $0.isOpen }.sorted { $0.due < $1.due }.first
            let freedom = outOpen.compactMap { $0.lastOpenDue }.max()
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ОСТАЛОСЬ ВЫПЛАТИТЬ").font(.caption.weight(.semibold)).tracking(0.8).opacity(0.75)
                    Text(Fmt.rubU(totalRem)).font(.system(size: 38, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                }
                if let x = next {
                    Button { pay = PayTarget(debt: x.debt, index: x.i) } label: {
                        let r = relDays(x.due)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ближайший платёж").font(.caption).opacity(0.75)
                            Text("\(x.debt.name) · \(Fmt.rubU(x.amount))").font(.headline)
                            Text("\(DF.short(x.due)), \(r.text)").font(.subheadline).foregroundStyle(r.bad ? Theme.exp : Color(.systemBackground).opacity(0.85))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.systemBackground).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if outOpen.isEmpty {
                    Text("Все ваши долги закрыты. Так держать.").opacity(0.85)
                }
                HStack(spacing: 10) {
                    DarkFlow(title: "Уже выплачено", value: Fmt.rubU(paidAll))
                    DarkFlow(title: "Свобода от долгов", value: freedom.map { DF.s($0, "LLL yyyy").replacingOccurrences(of: ".", with: "").capitalizedFirst } ?? "—")
                }
                if let f = freedom {
                    Text("Последний платёж — \(spanText(to: f)), если платить по графику.").font(.footnote).opacity(0.85)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color(.systemBackground))
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    @ViewBuilder private var overdueAlert: some View {
        let ov = allInstallments(debts).filter { $0.st == .overdue && $0.debt.isOut }.sorted { $0.due < $1.due }
        if let x = ov.first {
            Button { pay = PayTarget(debt: x.debt, index: x.i) } label: {
                AlertText(color: Theme.exp, text: "\(ov.count) \(plural(ov.count, "просроченный платёж", "просроченных платежа", "просроченных платежей")). \(x.debt.name): \(Fmt.rubU(x.amount)), срок был \(DF.short(x.due)). Нажмите, чтобы отметить оплату.")
            }
            .buttonStyle(.plain)
        }
    }

    private var tiles: some View {
        let inst = allInstallments(debts)
        let monthly = inst.filter { $0.debt.isOut && $0.due.sameMonth(Date()) }.reduce(0) { $0 + $1.plan }
        let avg = averageIncome(txs)
        let load: Double? = avg > 0 ? monthly / avg : nil
        let streak = onTimeStreak(debts)
        let loadColor: Color = load == nil ? .primary : (load! < 0.3 ? Theme.inc : (load! < 0.5 ? Theme.warn : Theme.exp))
        let loadSub = load == nil ? "нет доходов" : (load! < 0.3 ? "от дохода, норма" : (load! < 0.5 ? "от дохода, много" : "от дохода, опасно"))
        return HStack(spacing: 8) {
            Tile(title: "В этом месяце", value: Fmt.rubU(monthly), sub: "по графику", color: .primary)
            Tile(title: "Нагрузка", value: load.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", sub: loadSub, color: loadColor)
            Tile(title: "В срок подряд", value: "\(streak)", sub: streak >= 6 ? "железно" : (streak >= 3 ? "отличная серия" : plural(streak, "платёж", "платежа", "платежей")), color: streak >= 3 ? Theme.inc : .primary)
        }
    }

    // MARK: Календарь

    private var calendar: some View {
        let inst = allInstallments(debts)
        let byDay = Dictionary(grouping: inst) { $0.due.day0 }
        let list: [Inst] = (selDay.map { byDay[$0.day0] ?? [] } ?? inst.filter { $0.due.sameMonth(calMonth) }).sorted { $0.due < $1.due }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(DF.month(calMonth)).font(.headline)
                Spacer()
                HStack(spacing: 0) {
                    Button { calMonth = calMonth.addingMonths(-1); selDay = nil } label: { Image(systemName: "chevron.left").frame(width: 34, height: 30) }
                    Button("Сегодня") { calMonth = Date().startOfMonth; selDay = Date().day0 }.font(.subheadline.weight(.semibold)).padding(.horizontal, 6)
                    Button { calMonth = calMonth.addingMonths(1); selDay = nil } label: { Image(systemName: "chevron.right").frame(width: 34, height: 30) }
                }
                .padding(2)
                .background(Theme.soft, in: Capsule())
            }
            CalendarGrid(month: calMonth, byDay: byDay, selected: $selDay)
            FlowLayout(spacing: 12) {
                LegendDot(color: Theme.accent, text: "Предстоит")
                LegendDot(color: Theme.inc, text: "В срок")
                LegendDot(color: Theme.warn, text: "С опозданием")
                LegendDot(color: Theme.exp, text: "Просрочен")
            }
            Divider()
            HStack {
                Text((selDay.map { DF.s($0, "d MMMM") } ?? "Платежи в этом месяце").uppercased())
                Spacer()
                if !list.isEmpty { Text(Fmt.rubU(list.reduce(0) { $0 + $1.amount })) }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if list.isEmpty {
                Text(debts.isEmpty ? "Здесь появится график платежей" : "Платежей нет").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
            } else {
                ForEach(list) { x in
                    Button { pay = PayTarget(debt: x.debt, index: x.i) } label: { InstRow(x: x) }.buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    // MARK: Списки

    @ViewBuilder private var lists: some View {
        if !outOpen.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "Мои кредиты и долги")
                ForEach(outOpen.sorted { $0.remaining > $1.remaining }) { d in DebtLink(d: d) }
            }
            .card()
        }
        if !inOpen.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "Мне должны · \(Fmt.rubU(inOpen.reduce(0) { $0 + $1.remaining }))")
                ForEach(inOpen) { d in DebtLink(d: d) }
            }
            .card()
        }
        if !closed.isEmpty {
            DisclosureGroup("Закрытые долги · \(closed.count)") {
                ForEach(closed) { d in DebtLink(d: d) }
            }
            .font(.subheadline.weight(.semibold))
            .card()
        }
    }

    @ViewBuilder private var advice: some View {
        if outOpen.count > 1 || outOpen.contains(where: { $0.type == .micro }) {
            let micro = outOpen.filter { $0.type == .micro }.min { $0.remaining < $1.remaining }
            let rated = outOpen.filter { $0.rate > 0 }.max { $0.rate < $1.rate }
            let small = outOpen.min { $0.remaining < $1.remaining }
            let tip: (String, String, String) = {
                if let m = micro { return ("!", "Свободные деньги — сначала на «\(m.name)».", "Микрозаймы — самые дорогие деньги: у МФО ставка до 0,8% в день. Закройте его как можно раньше, остальное — по графику.") }
                if let r = rated { return ("%", "Метод лавины: досрочно гасите «\(r.name)».", "У него самая высокая ставка — \(Fmt.input(r.rate))% годовых. Каждый рубль досрочно экономит больше всего на процентах.") }
                let s = small!
                return ("1", "Метод снежного кома: закройте сначала «\(s.name)».", "Осталось всего \(Fmt.rubU(s.remaining)). Закрытый долг освобождает платёж и мотивирует гасить следующий. Укажите ставки — подскажу, где выгоднее.")
            }()
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "Что гасить первым")
                HStack(alignment: .top, spacing: 12) {
                    Text(tip.0).font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 36, height: 36)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tip.1).font(.body.weight(.semibold))
                        Text(tip.2).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .card()
        }
    }
}

// MARK: - Мелкие элементы

struct DarkFlow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).opacity(0.75)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct Tile: View {
    let title: String
    let value: String
    let sub: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AlertText: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
        }
        .padding(14)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct LegendDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

func statusColor(_ st: InstStatus) -> Color {
    switch st {
    case .ok: return Theme.inc
    case .late: return Theme.warn
    case .overdue: return Theme.exp
    case .due: return Theme.accent
    case .covered: return .secondary
    }
}

struct CalendarGrid: View {
    let month: Date
    let byDay: [Date: [Inst]]
    @Binding var selected: Date?

    var days: [Date] {
        let first = month.startOfMonth
        let offset = (cal.component(.weekday, from: first) + 5) % 7
        let count = offset + first.daysInMonth
        let cells = count <= 35 ? 35 : 42
        return (0..<cells).map { first.addingDays($0 - offset) }
    }

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(["пн", "вт", "ср", "чт", "пт", "сб", "вс"], id: \.self) { w in
                Text(w.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(days, id: \.self) { d in cell(d) }
        }
    }

    @ViewBuilder func cell(_ d: Date) -> some View {
        let xs = byDay[d.day0] ?? []
        let inMonth = d.sameMonth(month)
        let isSel = selected.map { $0.sameDay(d) } ?? false
        let isToday = d.sameDay(Date())
        Button {
            if !inMonth { return }
            selected = isSel ? nil : d.day0
        } label: {
            VStack(spacing: 3) {
                Text("\(d.dayNum)").font(.subheadline.weight(xs.isEmpty ? .regular : .semibold))
                HStack(spacing: 3) {
                    ForEach(Array(xs.prefix(3).enumerated()), id: \.offset) { _, x in
                        Circle().fill(isSel ? Color(.systemBackground) : statusColor(x.st)).frame(width: 6, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundStyle(isSel ? Color(.systemBackground) : (inMonth ? Color.primary : Color.secondary.opacity(0.5)))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSel ? Theme.ink : (xs.isEmpty || !inMonth ? Color.clear : Theme.soft))
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isToday && !isSel ? Theme.ink : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

struct InstRow: View {
    let x: Inst
    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text("\(x.due.dayNum)").font(.title3.weight(.semibold))
                Text(DF.s(x.due, "MMM").replacingOccurrences(of: ".", with: "")).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(x.debt.name).font(.body.weight(.medium)).lineLimit(1)
                Text((x.n > 1 ? "Платёж \(x.i + 1) из \(x.n)" : "Разовый платёж") + (x.debt.isOut ? "" : " · вам вернут"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.rubU(x.amount)).fontWeight(.semibold)
                StatusPill(st: x.st)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct DebtLink: View {
    let d: Debt
    var body: some View {
        NavigationLink(value: d.uid) {
            HStack(spacing: 12) {
                Ring(value: d.isClosed ? 1 : d.progress, color: d.isClosed ? Theme.inc : d.type.color)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(d.type.name).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(d.type.color, in: RoundedRectangle(cornerRadius: 5))
                        Text(d.name).font(.body.weight(.semibold)).lineLimit(1)
                    }
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(Fmt.rubU(d.remaining)).fontWeight(.semibold)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
    var subtitle: String {
        var parts: [String] = []
        if !d.lender.isEmpty { parts.append(d.lender) }
        if d.isClosed { parts.append("Закрыт") }
        else if let nx = d.nextInst { parts.append("\(nx.st == .overdue ? "Просрочен" : "След.") \(DF.short(nx.due)) · \(Fmt.rubU(nx.amount))") }
        return parts.joined(separator: " · ")
    }
}
