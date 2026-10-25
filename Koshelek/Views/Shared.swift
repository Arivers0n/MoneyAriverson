import SwiftUI
import SwiftData

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.font(.caption.weight(.bold)); configuration.title }
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
        .cardBG(Capsule())
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
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(groups) { g in
                let net = g.items.reduce(0) { $0 + $1.signedAmount }
                HStack {
                    Text(dayLabel(g.day))
                    Spacer()
                    Text(Fmt.signed(net)).foregroundStyle(net > 0 ? Theme.inc.opacity(0.8) : Color.secondary.opacity(0.7))
                }
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 14).padding(.bottom, 2)
                ForEach(g.items) { t in
                    Button { router.show(.editTx(t)) } label: { row(t) }
                        .buttonStyle(Pressable(scale: 0.98))
                        // лента открывается десятки раз в день — без поочерёдного выплывания;
                        // анимируются только добавление и удаление строки
                        .transition(Motion.moves
                            ? .asymmetric(insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity), removal: .scale(scale: 0.96).combined(with: .opacity))
                            : .opacity)
                        .contextMenu {
                            Button { router.show(.editTx(t)) } label: { Label("Изменить", systemImage: "pencil") }
                            Button { TxActions.repeatToday(t) } label: { Label("Повторить сегодня", systemImage: "arrow.clockwise") }
                            Button {
                                UIPasteboard.general.string = "\(Catalog.cat(t.cat).name) \(Fmt.rub(t.signedAmount))\(t.note.isEmpty ? "" : " — " + t.note)"
                                Haptic.tap(); router.say("Скопировано")
                            } label: { Label("Скопировать", systemImage: "doc.on.doc") }
                            Button(role: .destructive) { TxActions.delete(t) } label: { Label("Удалить", systemImage: "trash") }
                        }
                }
            }
        }
        .animation(Motion.spring, value: txs.count)
    }

    func dayLabel(_ d: Date) -> String {
        let n = daysBetween(d, Date())
        if n == 0 { return "Сегодня" }
        if n == 1 { return "Вчера" }
        return DF.s(d, "EE, d MMMM").capitalizedFirst
    }

    @ViewBuilder func row(_ t: Tx) -> some View {
        RowCard {
            if t.kind == .tr {
                CategoryTile(symbol: "arrow.left.arrow.right", color: .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Перевод").font(.title3.weight(.medium))
                    Text("\(accName(t.accID)) → \(accName(t.toID))").font(.body).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Fmt.rubU(t.amount)).font(.title3.weight(.medium)).foregroundStyle(.secondary)
            } else {
                let c = Catalog.cat(t.cat)
                CategoryTile(symbol: c.symbol, color: c.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.title3.weight(.medium)).lineLimit(1)
                    let sub = [t.note, accounts.count > 1 ? accName(t.accID) : "", SyncEngine.shared.memberName(t.author) ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty { Text(sub).font(.body).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Text((t.kind == .inc ? "+" : "-") + Fmt.rubU(t.amount))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(t.kind == .inc ? Theme.inc : Color.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
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
                    Button("Готово") {
                        budget = max(0, parseAmount(text) ?? 0)
                        SyncEngine.shared.setBudget(budget)
                        dismiss()
                    }
                }
            }
            .onAppear { text = Fmt.input(budget) }
        }
        .presentationDetents([.medium])
    }
}

/// Быстрые действия с операциями: повтор, удаление с отменой.
@MainActor
enum TxActions {
    static var ctx: ModelContext { Store.container.mainContext }

    @discardableResult
    static func repeatToday(_ t: Tx, toast: Bool = true) -> Tx {
        let n = Tx(kind: t.kind, amount: t.amount, cat: t.cat, note: t.note, date: Date(), accID: t.accID, toID: t.toID)
        withAnimation(Motion.spring) { ctx.insert(n) }
        ctx.commit()
        Haptic.success()
        if toast {
            let sign = t.kind == .inc ? "+" : (t.kind == .exp ? "−" : "")
            Router.shared.say("\(Catalog.cat(t.cat).name) \(sign)\(Fmt.rubU(t.amount)) — записано") { delete(n, toast: false) }
        }
        return n
    }

    static func delete(_ t: Tx, toast: Bool = true) {
        Haptic.warning()
        withAnimation(Motion.spring) { t.softDelete() }
        ctx.commit()
        if toast {
            Router.shared.say("Операция удалена") {
                withAnimation(Motion.spring) { t.removed = false }
                ctx.commit()
            }
        }
    }
}

/// Частые операции: одинаковые категория + сумма + заметка, повторявшиеся за 3 месяца.
struct FrequentTx: Identifiable {
    let id: String
    let sample: Tx
    let count: Int
}

func frequentTxs(_ txs: [Tx], limit: Int = 8) -> [FrequentTx] {
    let from = Date().addingDays(-90)
    var groups: [String: (Tx, Int)] = [:]
    for t in txs where t.date >= from && t.kind != .tr && t.cat != "loans" && t.cat != "debtback" && t.recID == nil {
        let k = "\(t.kindRaw)|\(t.cat)|\(Int(t.amount))|\(t.note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
        if let g = groups[k] { groups[k] = (g.0.date > t.date ? g.0 : t, g.1 + 1) } else { groups[k] = (t, 1) }
    }
    return groups.filter { $0.value.1 >= 2 }
        .map { FrequentTx(id: $0.key, sample: $0.value.0, count: $0.value.1) }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.sample.date > $1.sample.date }
        .prefix(limit).map { $0 }
}

/// Блок «Частое»: одно касание — и операция записана сегодняшним днём.
struct QuickBlock: View {
    let txs: [Tx]
    @ObservedObject private var ap = Appearance.shared
    var body: some View {
        let items = frequentTxs(txs)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Частое", systemImage: "bolt.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if !items.isEmpty { Text("касание — записать").font(.caption).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 4)
            if items.isEmpty {
                Text("Здесь появятся траты, которые вы часто повторяете — кофе, проезд, обеды. Записывать их можно будет одним касанием.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .cardBG(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, f in
                            QuickChip(t: f.sample, masked: ap.hideAmounts)
                                .appearIn(i)
                        }
                    }
                    .padding(.horizontal, 2).padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct QuickChip: View {
    let t: Tx
    let masked: Bool
    @State private var pop = false
    var body: some View {
        let c = Catalog.cat(t.cat)
        Button {
            TxActions.repeatToday(t)
            if Motion.enabled {
                withAnimation(Motion.pressDown) { pop = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(Motion.pop) { pop = false } }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: pop ? "checkmark" : c.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.color)
                    .frame(width: 30, height: 30)
                    .background(c.color.opacity(0.18), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.note.isEmpty ? c.name : t.note.capitalizedFirst).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(masked ? "•••" : (t.kind == .inc ? "+" : "") + Fmt.rubU(t.amount))
                        .font(.caption).foregroundStyle(t.kind == .inc ? Theme.inc : .secondary)
                }
                .frame(maxWidth: 130, alignment: .leading)
            }
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
            .cardBG(Capsule())
            .scaleEffect(pop && Motion.moves ? 1.06 : 1)
        }
        .buttonStyle(Pressable(scale: 0.95))
    }
}
