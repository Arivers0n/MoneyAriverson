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
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { router.show(.editTx(t)) } label: { Label("Изменить", systemImage: "pencil") }
                            Button(role: .destructive) {
                                t.softDelete()
                                Store.container.mainContext.commit()
                            } label: { Label("Удалить", systemImage: "trash") }
                        }
                }
            }
        }
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
