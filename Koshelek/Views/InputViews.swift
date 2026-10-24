import SwiftUI
import SwiftData

// MARK: - Операция вручную

struct TxForm: View {
    let tx: Tx?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var router: Router
    @Query(sort: \Account.created) private var accs: [Account]
    @AppStorage("lastAcc") private var lastAcc = ""

    @State private var kind: TxKind = .exp
    @State private var amount = ""
    @State private var cat = "food"
    @State private var acc: UUID?
    @State private var to: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var err: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Тип", selection: $kind) {
                        Text("Расход").tag(TxKind.exp)
                        Text("Доход").tag(TxKind.inc)
                        if accs.count >= 2 { Text("Перевод").tag(TxKind.tr) }
                    }
                    .pickerStyle(.segmented)
                    AmountField(text: $amount)
                }
                if kind != .tr {
                    Section("Категория") {
                        FlowLayout {
                            ForEach(Catalog.list(kind)) { c in
                                Chip(title: c.name, color: c.color, selected: cat == c.id) { cat = c.id }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if !accs.isEmpty {
                    Section(kind == .tr ? "Откуда" : "Счёт") {
                        FlowLayout {
                            ForEach(accs) { a in Chip(title: a.name, color: Color(hex: a.hex), selected: acc == a.uid) { acc = a.uid } }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if kind == .tr {
                    Section("Куда") {
                        FlowLayout {
                            ForEach(accs.filter { $0.uid != acc }) { a in Chip(title: a.name, color: Color(hex: a.hex), selected: to == a.uid) { to = a.uid } }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                    TextField("Заметка", text: $note)
                }
                if let err { Section { Text(err).foregroundStyle(Theme.exp) } }
                if tx != nil {
                    Section {
                        Button("Удалить операцию", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(tx == nil ? "Новая операция" : "Операция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).fontWeight(.semibold) }
            }
            .confirmationDialog("Удалить операцию?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let tx { ctx.delete(tx); try? ctx.save() }
                    dismiss()
                }
            }
            .onChange(of: kind) { _, k in if k != .tr { cat = Catalog.valid(cat, for: k) } }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let t = tx {
            kind = t.kind; amount = Fmt.input(t.amount); cat = t.cat; acc = t.accID; to = t.toID; date = t.date; note = t.note
        } else {
            acc = accs.first { $0.uid.uuidString == lastAcc }?.uid ?? accs.first?.uid
        }
    }

    private func save() {
        guard let v = parseAmount(amount), v > 0 else { err = "Введите сумму больше нуля."; return }
        if kind == .tr && (acc == nil || to == nil || acc == to) { err = "Выберите два разных счёта."; return }
        if let t = tx {
            t.kind = kind; t.amount = v; t.cat = kind == .tr ? "" : cat; t.accID = acc; t.toID = kind == .tr ? to : nil
            t.date = date.noon; t.note = note
        } else {
            ctx.insert(Tx(kind: kind, amount: v, cat: kind == .tr ? "" : cat, note: note, date: date, accID: acc, toID: kind == .tr ? to : nil))
        }
        if let acc { lastAcc = acc.uuidString }
        try? ctx.save()
        dismiss()
        router.say(tx == nil ? "Добавлено" : "Сохранено")
    }
}

// MARK: - Счёт

struct AccountForm: View {
    let account: Account?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accs: [Account]
    @State private var name = ""
    @State private var start = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if account == nil {
                    Section {
                        FlowLayout {
                            ForEach(["Карта", "Наличные", "Накопительный", "Кредитка"], id: \.self) { p in
                                Chip(title: p, selected: name == p) { name = p }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    TextField("Название", text: $name)
                    TextField("Сколько на нём сейчас, ₽", text: $start).keyboardType(.numbersAndPunctuation)
                } footer: { Text("Баланс дальше считается сам по операциям с этим счётом.") }
                if account != nil {
                    Section { Button("Удалить счёт", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(account == nil ? "Новый счёт" : "Счёт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty else { return }
                        let s = parseAmount(start) ?? 0
                        if let a = account { a.name = n; a.start = s }
                        else { ctx.insert(Account(name: n, start: s, hex: Theme.palette[accs.count % Theme.palette.count])) }
                        try? ctx.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Операции останутся, но без счёта. Удалить?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let a = account { ctx.delete(a); try? ctx.save() }
                    dismiss()
                }
            }
            .onAppear {
                if let a = account { name = a.name; start = Fmt.input(a.start) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Проверка распознанного

struct ReviewSheet: View {
    let payload: ReviewPayload
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.created) private var accs: [Account]
    @Query private var debts: [Debt]
    @Query private var goals: [Goal]
    @AppStorage("lastAcc") private var lastAcc = ""
    @State private var items: [ParsedItem] = []
    @State private var acc: UUID?

    var onCount: Int { items.filter { $0.on }.count }

    var body: some View {
        NavigationStack {
            List {
                if !payload.subtitle.isEmpty {
                    Section { Text(payload.subtitle).font(.subheadline).foregroundStyle(.secondary) }
                }
                if !accs.isEmpty && items.contains(where: { $0.isMoney }) {
                    Section("Счёт") {
                        FlowLayout {
                            ForEach(accs) { a in Chip(title: a.name, color: Color(hex: a.hex), selected: acc == a.uid) { acc = a.uid } }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    ForEach($items) { $it in
                        ReviewRow(item: $it, debts: debts, goals: goals, accounts: accs)
                    }
                }
            }
            .navigationTitle(items.count == 1 ? "Проверьте" : "Проверьте \(items.count) \(plural(items.count, "запись", "записи", "записей"))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text(onCount == 0 ? "Ничего не выбрано" : "Добавить \(onCount)")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(onCount == 0)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.bar)
            }
            .onAppear {
                if items.isEmpty { items = payload.items }
                acc = accs.first { $0.uid.uuidString == lastAcc }?.uid ?? accs.first?.uid
            }
        }
    }

    private func save() {
        for i in items.indices where items[i].isMoney { items[i].amount = parseAmount(items[i].amountText) ?? 0 }
        Task {
            if items.contains(where: { $0.on && $0.kind == .task }) { await TaskStore.shared.requestAccess() }
            let res = Saver.apply(items, account: acc, ctx: ctx)
            if let acc { lastAcc = acc.uuidString }
            router.finishSave(res)
        }
    }
}

struct ReviewRow: View {
    @Binding var item: ParsedItem
    let debts: [Debt]
    let goals: [Goal]
    var accounts: [Account] = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { item.on.toggle() } label: {
                Image(systemName: item.on ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(item.on ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 8) {
                switch item.kind {
                case .debt: debtHeader
                case .goal: goalHeader
                case .tx: categoryMenu
                case .rec: recHeader
                case .task: lifeHeader(symbol: "checklist", color: Theme.accent, title: "Задача")
                case .shop: lifeHeader(symbol: "cart", color: Theme.inc, title: "В список покупок")
                case .habit: lifeHeader(symbol: "flame.fill", color: Theme.warn, title: "Привычка выполнена")
                }
                if item.isMoney {
                    HStack {
                        DatePicker("", selection: $item.date, displayedComponents: .date).labelsHidden()
                        Spacer()
                        TextField("0", text: $item.amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.headline)
                            .frame(maxWidth: 120)
                        Text("₽").foregroundStyle(.secondary)
                    }
                } else if item.kind == .task {
                    TextField("Что сделать", text: $item.note).font(.body)
                    Toggle("Срок", isOn: $item.hasDue).font(.subheadline)
                    if item.hasDue {
                        DatePicker("", selection: $item.date, displayedComponents: item.dueTime ? [.date, .hourAndMinute] : [.date])
                            .labelsHidden()
                    }
                } else if item.kind == .shop {
                    TextField("Товар", text: $item.note).font(.body)
                } else {
                    Text(item.note).font(.body)
                }
                if item.kind == .tx || item.kind == .rec {
                    TextField(item.kind == .rec ? "Название" : "Заметка", text: $item.note).font(.subheadline)
                }
                if let a = accounts.first(where: { $0.uid == item.accID }) {
                    Label(a.name, systemImage: "creditcard").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(item.on ? 1 : 0.5)
        .padding(.vertical, 4)
    }

    private var categoryMenu: some View {
        Menu {
            Section("Расходы") {
                ForEach(Catalog.expense) { c in Button(c.name) { item.type = .exp; item.cat = c.id } }
            }
            Section("Доходы") {
                ForEach(Catalog.income) { c in Button(c.name) { item.type = .inc; item.cat = c.id } }
            }
        } label: {
            let c = Catalog.cat(item.cat)
            HStack(spacing: 8) {
                IconBadge(symbol: c.symbol, color: c.color, size: 28)
                Text(c.name).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                Text(item.type == .inc ? "доход" : "расход").font(.caption).foregroundStyle(item.type == .inc ? Theme.inc : Color.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var debtHeader: some View {
        if let d = debts.first(where: { $0.uid == item.debtID }) {
            HStack(spacing: 8) {
                IconBadge(symbol: "building.columns.fill", color: d.type.color, size: 28)
                Text("\(d.isOut ? "Платёж" : "Вам вернули"): \(d.name)").font(.body.weight(.semibold))
            }
            if let ni = d.nextInst {
                Text("Отметится платёж \(ni.i + 1) из \(ni.n) (срок \(DF.short(ni.due))) и попадёт в \(d.isOut ? "расходы" : "доходы")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func lifeHeader(symbol: String, color: Color, title: String) -> some View {
        HStack(spacing: 8) {
            SoftIcon(symbol: symbol, color: color, size: 28)
            Text(title).font(.body.weight(.semibold))
        }
    }

    @ViewBuilder private var recHeader: some View {
        let c = Catalog.cat(item.cat)
        HStack(spacing: 8) {
            SoftIcon(symbol: "repeat", color: c.color, size: 28)
            Text("Новый регулярный платёж").font(.body.weight(.semibold))
        }
        Text(item.recYearly ? "Раз в год, \(item.recDay)-го числа · \(c.name)" : "Каждый месяц, \(item.recDay)-го числа · \(c.name)")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var goalHeader: some View {
        if let g = goals.first(where: { $0.uid == item.goalID }) {
            HStack(spacing: 8) {
                IconBadge(symbol: "banknote.fill", color: Color(hex: g.hex), size: 28)
                Text("\(item.sign < 0 ? "Взять из" : "Положить в") «\(g.name)»").font(.body.weight(.semibold))
            }
        }
    }
}
