import SwiftUI
import SwiftData

struct GoalTarget: Identifiable { let id = UUID(); let goal: Goal? }
struct RecTarget: Identifiable { let id = UUID(); let rec: Recurring? }

struct PlansView: View {
    @EnvironmentObject var router: Router
    @Query(sort: \Goal.created) private var goals: [Goal]
    @Query(sort: \Recurring.day) private var recs: [Recurring]
    @Query private var txs: [Tx]
    @State private var goalEdit: GoalTarget?
    @State private var goalAdd: Goal?
    @State private var recEdit: RecTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    WalletHeader(title: "Планы", onAdd: nil)
                    SectionSwitcher(titles: WalletView.sections, selection: $router.wallet)
                    goalsCard
                    recsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $goalEdit) { t in GoalForm(goal: t.goal) }
            .sheet(item: $goalAdd) { g in GoalAddSheet(goal: g) }
            .sheet(item: $recEdit) { t in RecurringForm(rec: t.rec) }
        }
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Копилки и цели", action: "+ Цель") { goalEdit = GoalTarget(goal: nil) }
            if goals.isEmpty {
                EmptyNote(title: "Копите на что-то?", text: "Создайте копилку: отпуск, подушка безопасности, новый телефон. Приложение посчитает, сколько откладывать в месяц.")
            }
            ForEach(goals) { g in
                GoalRow(goal: g, onEdit: { goalEdit = GoalTarget(goal: g) }, onAdd: { goalAdd = g })
                if g.uid != goals.last?.uid { Divider() }
            }
        }
        .card()
    }

    private var recsCard: some View {
        let perMonth = recs.reduce(0) { $0 + $1.perMonth }
        let now = Date()
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Подписки и регулярные", action: "+ Платёж") { recEdit = RecTarget(rec: nil) }
            if recs.isEmpty {
                EmptyNote(title: "Подписки и обязательные платежи", text: "Интернет, связь, Яндекс Плюс, аренда, зарплата. Будут напоминать о себе и записываться в одно касание.")
            } else {
                HStack(spacing: 8) {
                    Stat(title: "В месяц", value: Fmt.rubU(perMonth))
                    Stat(title: "В год", value: Fmt.rubU(perMonth * 12))
                }
                ForEach(recs) { r in
                    Button { recEdit = RecTarget(rec: r) } label: {
                        let c = Catalog.cat(r.cat)
                        HStack(spacing: 12) {
                            IconBadge(symbol: c.symbol, color: c.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.body.weight(.medium)).lineLimit(1)
                                Text(recLine(r, c))
                                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text((r.kind == .inc ? "+" : "") + Fmt.rubU(r.amount)).fontWeight(.semibold).foregroundStyle(r.kind == .inc ? Theme.inc : Color.primary)
                                recStatus(r, now: now)
                            }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private func recLine(_ r: Recurring, _ c: Category) -> String {
        let when: String
        if r.yearly {
            let d = cal.date(from: DateComponents(year: 2026, month: r.month, day: 1)) ?? Date()
            when = "Раз в год, \(r.day) \(DF.s(d, "MMMM"))"
        } else {
            when = "Каждый месяц, \(r.day)-го"
        }
        return when + " · " + c.name
    }

    @ViewBuilder private func recStatus(_ r: Recurring, now: Date) -> some View {
        if let d = r.due(in: now) {
            if r.isRecorded(in: now, txs: txs) { Pill(text: "Записан", color: Theme.inc) }
            else if d.day0 <= now.day0 { Pill(text: "Пора записать", color: Theme.exp) }
            else { Pill(text: DF.short(d), color: Theme.accent) }
        } else {
            Pill(text: "не в этом месяце", color: .secondary)
        }
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct GoalRow: View {
    let goal: Goal
    let onEdit: () -> Void
    let onAdd: () -> Void
    var body: some View {
        let saved = goal.saved, done = goal.target > 0 && saved >= goal.target
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.name).font(.body.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(Fmt.rubU(saved)).fontWeight(.semibold)
                Text("из \(Fmt.rubU(goal.target))").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Bar(value: goal.target > 0 ? saved / goal.target : 0, color: Color(hex: goal.hex))
            HStack {
                Text(footer(saved: saved, done: done)).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Изм.", action: onEdit).buttonStyle(.bordered).controlSize(.small)
                Button("Пополнить", action: onAdd).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }
    func footer(saved: Double, done: Bool) -> String {
        if done { return "Цель достигнута!" }
        var s = "Осталось \(Fmt.rubU(goal.target - saved))"
        if let dl = goal.deadline {
            if dl.day0 < Date().day0 { s += " · срок прошёл" }
            else {
                let ms = max(1, monthsBetween(Date(), dl) + 1)
                s += " · по \(Fmt.rubU((goal.target - saved) / Double(ms))) в мес."
            }
        }
        return s
    }
}

// MARK: - Формы

struct GoalForm: View {
    let goal: Goal?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [Goal]
    @State private var name = ""
    @State private var target = ""
    @State private var hasDeadline = false
    @State private var deadline = Date().addingMonths(6)
    @State private var hex = Theme.palette[0]
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("На что копим", text: $name)
                    LabeledContent("Сколько нужно") {
                        TextField("60 000", text: $target).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Toggle("К определённой дате", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("Дата", selection: $deadline, displayedComponents: .date) }
                }
                Section("Цвет") {
                    HStack {
                        ForEach(Theme.palette, id: \.self) { h in
                            Circle().fill(Color(hex: h)).frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: hex == h ? 2.5 : 0))
                                .onTapGesture { hex = h }
                        }
                    }
                }
                if goal != nil { Section { Button("Удалить копилку", role: .destructive) { confirmDelete = true } } }
            }
            .navigationTitle(goal == nil ? "Новая копилка" : "Копилка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard let t = parseAmount(target), t > 0, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        if let g = goal { g.name = name; g.target = t; g.deadline = hasDeadline ? deadline.noon : nil; g.hex = hex }
                        else { ctx.insert(Goal(name: name, target: t, deadline: hasDeadline ? deadline.noon : nil, hex: hex)) }
                        try? ctx.save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Удалить копилку?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let g = goal { ctx.delete(g); try? ctx.save() }; dismiss() }
            }
            .onAppear {
                if let g = goal {
                    name = g.name; target = Fmt.input(g.target); hasDeadline = g.deadline != nil; deadline = g.deadline ?? deadline; hex = g.hex
                } else { hex = Theme.palette[goals.count % Theme.palette.count] }
            }
        }
    }
}

struct GoalAddSheet: View {
    let goal: Goal
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var router: Router
    @Query(sort: \Account.created) private var accs: [Account]
    @AppStorage("lastAcc") private var lastAcc = ""
    @State private var take = false
    @State private var amount = ""
    @State private var toBudget = false
    @State private var err: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $take) {
                        Text("Положить").tag(false)
                        Text("Взять").tag(true)
                    }
                    .pickerStyle(.segmented)
                    AmountField(text: $amount)
                } header: { Text("В копилке \(Fmt.rubU(goal.saved)) из \(Fmt.rubU(goal.target))") }
                if !take { Section { Toggle("Учесть в расходах месяца", isOn: $toBudget) } }
                if let err { Section { Text(err).foregroundStyle(Theme.exp) } }
            }
            .navigationTitle(goal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(take ? "Взять" : "Положить", action: save).fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let v = parseAmount(amount), v > 0 else { err = "Введите сумму больше нуля."; return }
        let before = goal.saved
        if take && v > before { err = "В копилке только \(Fmt.rubU(before))."; return }
        var l = goal.log
        l.append(GoalEntry(date: Date().noon, amount: take ? -v : v))
        goal.log = l
        if !take && toBudget {
            let acc = accs.first { $0.uid.uuidString == lastAcc }?.uid ?? accs.first?.uid
            ctx.insert(Tx(kind: .exp, amount: v, cat: "savings", note: goal.name, date: Date(), accID: acc))
        }
        try? ctx.save()
        dismiss()
        if !take && before < goal.target && goal.saved >= goal.target {
            router.celebrate = ("Цель «\(goal.name)» достигнута!", "Накоплено \(Fmt.rubU(goal.saved)). Время тратить с удовольствием.")
        } else {
            router.say(take ? "Взято \(Fmt.rubU(v))" : "+\(Fmt.rubU(v)) в «\(goal.name)»")
        }
    }
}

struct RecurringForm: View {
    let rec: Recurring?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var kind: TxKind = .exp
    @State private var cat = "subs"
    @State private var day = Date().dayNum
    @State private var yearly = false
    @State private var month = Date().monthNum
    @State private var confirmDelete = false

    let presets: [(String, Double, String)] = [("Яндекс Плюс", 399, "subs"), ("Интернет", 700, "phone"), ("Связь", 500, "phone"),
                                               ("Аренда", 25000, "home"), ("ЖКУ", 5000, "home"), ("Зарплата", 0, "salary")]

    var body: some View {
        NavigationStack {
            Form {
                if rec == nil {
                    Section {
                        FlowLayout {
                            ForEach(presets.indices, id: \.self) { i in
                                let p = presets[i]
                                Chip(title: p.0, selected: name == p.0) {
                                    name = p.0; if p.1 > 0 { amount = Fmt.input(p.1) }
                                    cat = p.2; kind = Catalog.cat(p.2).kind
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    Picker("Тип", selection: $kind) {
                        Text("Расход").tag(TxKind.exp)
                        Text("Доход").tag(TxKind.inc)
                    }
                    .pickerStyle(.segmented)
                    TextField("Название", text: $name)
                    LabeledContent("Сумма") {
                        TextField("399", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                Section("Категория") {
                    FlowLayout {
                        ForEach(Catalog.list(kind)) { c in Chip(title: c.name, color: c.color, selected: cat == c.id) { cat = c.id } }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Picker("Как часто", selection: $yearly) {
                        Text("Каждый месяц").tag(false)
                        Text("Раз в год").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Stepper("Число месяца: \(day)", value: $day, in: 1...31)
                    if yearly {
                        Picker("Месяц", selection: $month) {
                            ForEach(1...12, id: \.self) { m in
                                Text(DF.s(cal.date(from: DateComponents(year: 2026, month: m, day: 1)) ?? Date(), "LLLL").capitalizedFirst).tag(m)
                            }
                        }
                    }
                }
                if rec != nil { Section { Button("Удалить", role: .destructive) { confirmDelete = true } } }
            }
            .navigationTitle(rec == nil ? "Регулярный платёж" : rec!.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard let v = parseAmount(amount), v > 0, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let c = Catalog.valid(cat, for: kind)
                        if let r = rec { r.name = name; r.amount = v; r.kind = kind; r.cat = c; r.day = day; r.yearly = yearly; r.month = month }
                        else { ctx.insert(Recurring(name: name, amount: v, kind: kind, cat: c, day: day, yearly: yearly, month: month)) }
                        try? ctx.save()
                        Notifier.reschedule(ctx: ctx)
                        dismiss()
                    }
                }
            }
            .onChange(of: kind) { _, k in cat = Catalog.valid(cat, for: k) }
            .confirmationDialog("Удалить регулярный платёж?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let r = rec { ctx.delete(r); try? ctx.save() }; dismiss() }
            }
            .onAppear {
                if let r = rec { name = r.name; amount = Fmt.input(r.amount); kind = r.kind; cat = r.cat; day = r.day; yearly = r.yearly; month = r.month }
            }
        }
    }
}
