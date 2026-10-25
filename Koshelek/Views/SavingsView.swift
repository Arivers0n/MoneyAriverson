import SwiftUI
import SwiftData

struct GoalTarget: Identifiable { let id = UUID(); let goal: Goal? }
struct RecTarget: Identifiable { let id = UUID(); let rec: Recurring? }

// MARK: - Копилки

struct SavingsView: View {
    @EnvironmentObject var router: Router
    /// Запрос «создать копилку» снаружи (кнопка «+» в шапке).
    @Binding var addRequest: Int
    @Query(sort: \Goal.created) private var qGoals: [Goal]
    private var goals: [Goal] { qGoals.live }
    @Query(sort: \Tx.date, order: .reverse) private var qTxs: [Tx]
    private var txs: [Tx] { qTxs.live }
    @State private var goalEdit: GoalTarget?
    @State private var goalAdd: Goal?

    var active: [Goal] { goals.filter { $0.target <= 0 || $0.saved < $0.target } }
    var done: [Goal] { goals.filter { $0.target > 0 && $0.saved >= $0.target } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            if goals.isEmpty { emptyState }
            ForEach(active) { g in
                GoalCard(goal: g, onEdit: { goalEdit = GoalTarget(goal: g) }, onAdd: { goalAdd = g })
            }
            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Достигнуто").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(done) { g in
                        GoalCard(goal: g, onEdit: { goalEdit = GoalTarget(goal: g) }, onAdd: { goalAdd = g })
                    }
                }
            }
            tips
        }
        .sheet(item: $goalEdit) { t in GoalForm(goal: t.goal) }
        .sheet(item: $goalAdd) { g in GoalAddSheet(goal: g) }
        .onChange(of: addRequest) { _, _ in goalEdit = GoalTarget(goal: nil) }
    }

    private var hero: some View {
        let total = Savings.totalSaved(goals), month = Savings.savedThisMonth(goals)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Накоплено").font(.subheadline).foregroundStyle(.secondary)
            Text(Fmt.rubU(total)).font(.system(size: 48, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1).contentTransition(.numericText())
            if month != 0 {
                Label((month > 0 ? "+" : "−") + Fmt.rubU(month) + " в этом месяце", systemImage: month > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(month > 0 ? Theme.inc : Theme.exp)
                    .labelStyle(TightLabel())
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Начните копить").font(.title3.weight(.semibold))
            Text("Создайте копилку и включите автоправила: например, откладывать 10% с каждой зарплаты или округлять каждую трату до 100 ₽ и складывать сдачу.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { goalEdit = GoalTarget(goal: nil) } label: {
                Label("Создать копилку", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    @ViewBuilder private var tips: some View {
        let cushion = Savings.cushionTarget(txs)
        if cushion > 0 && !goals.contains(where: { $0.name.lowercased().contains("подушк") }) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Подушка безопасности", systemImage: "shield.lefthalf.filled").font(.subheadline.weight(.semibold))
                Text("Запас на 3 месяца ваших расходов — около \(Fmt.rubU(cushion)). Он спасает при потере работы или болезни и избавляет от новых кредитов.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Создать подушку") { goalEdit = GoalTarget(goal: nil); UserDefaults.standard.set(cushion, forKey: "cushionPreset") }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

struct GoalCard: View {
    let goal: Goal
    let onEdit: () -> Void
    let onAdd: () -> Void
    var body: some View {
        let color = Color(hex: goal.hex)
        let saved = goal.saved
        let p = goal.target > 0 ? saved / goal.target : 0
        let fc = Savings.forecast(goal)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: goal.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name).font(.headline).lineLimit(1)
                    Text(goal.target > 0 ? "\(Fmt.rubU(saved)) из \(Fmt.rubU(goal.target))" : Fmt.rubU(saved))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if goal.target > 0 {
                    Text("\(Int(min(1, p) * 100))%").font(.title3.weight(.bold)).foregroundStyle(color)
                }
            }
            if goal.target > 0 { Bar(value: p, color: color, height: 8) }
            if let fc {
                Text(fc.text).font(.footnote).foregroundStyle(fc.good ? Color.secondary : Theme.warn)
            } else if goal.target > 0 && saved >= goal.target {
                Text("Цель достигнута 🎉").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inc)
            }
            let rules = ruleText
            if !rules.isEmpty {
                Label(rules, systemImage: "wand.and.stars").font(.caption).foregroundStyle(.secondary).labelStyle(TightLabel())
            }
            HStack(spacing: 10) {
                Button(action: onAdd) {
                    Text("Пополнить").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(.white).background(color, in: Capsule())
                }
                Button(action: onEdit) {
                    Text("Настроить").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Theme.soft, in: Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    var ruleText: String {
        var r: [String] = []
        if goal.autoPercent > 0 { r.append("\(Fmt.input(goal.autoPercent))% с каждого дохода") }
        if goal.roundUp > 0 { r.append("сдача с трат до \(goal.roundUp) ₽") }
        return r.joined(separator: " · ")
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

// MARK: - Регулярные платежи (показываются на вкладке «Платежи»)

struct RecurringCard: View {
    @Query(sort: \Recurring.day) private var qRecs: [Recurring]
    private var recs: [Recurring] { qRecs.live }
    @Query private var qTxs: [Tx]
    private var txs: [Tx] { qTxs.live }
    @State private var recEdit: RecTarget?

    var body: some View {
        let perMonth = recs.reduce(0) { $0 + $1.perMonth }
        let now = Date()
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Подписки и регулярные", action: "+ Платёж") { recEdit = RecTarget(rec: nil) }
            if recs.isEmpty {
                Text("Интернет, связь, Яндекс Плюс, аренда, зарплата. Будут напоминать о себе и записываться в одно касание. Можно сказать голосом: «подписка Яндекс 399 каждый месяц 15-го».")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Stat(title: "В месяц", value: Fmt.rubU(perMonth))
                    Stat(title: "В год", value: Fmt.rubU(perMonth * 12))
                }
                ForEach(recs) { r in
                    Button { recEdit = RecTarget(rec: r) } label: {
                        let c = Catalog.cat(r.cat)
                        HStack(spacing: 12) {
                            SoftIcon(symbol: c.symbol, color: c.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.body.weight(.medium)).lineLimit(1)
                                Text(line(r, c)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text((r.kind == .inc ? "+" : "") + Fmt.rubU(r.amount)).fontWeight(.semibold).foregroundStyle(r.kind == .inc ? Theme.inc : Color.primary)
                                status(r, now: now)
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
        .sheet(item: $recEdit) { t in RecurringForm(rec: t.rec) }
    }

    private func line(_ r: Recurring, _ c: Category) -> String {
        let when: String
        if r.yearly {
            let d = cal.date(from: DateComponents(year: 2026, month: r.month, day: 1)) ?? Date()
            when = "Раз в год, \(r.day) \(DF.s(d, "MMMM"))"
        } else { when = "Каждый месяц, \(r.day)-го" }
        return when + " · " + c.name
    }

    @ViewBuilder private func status(_ r: Recurring, now: Date) -> some View {
        if let d = r.due(in: now) {
            if r.isRecorded(in: now, txs: txs) { Pill(text: "Записан", color: Theme.inc) }
            else if d.day0 <= now.day0 { Pill(text: "Пора записать", color: Theme.exp) }
            else { Pill(text: DF.short(d), color: Theme.accent) }
        } else {
            Pill(text: "не в этом месяце", color: .secondary)
        }
    }
}

// MARK: - Формы копилки

struct GoalForm: View {
    let goal: Goal?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var qGoals: [Goal]
    private var goals: [Goal] { qGoals.live }
    @Query private var qTxs: [Tx]
    private var txs: [Tx] { qTxs.live }

    @State private var name = ""
    @State private var target = ""
    @State private var hasDeadline = false
    @State private var deadline = Date().addingMonths(6)
    @State private var hex = Theme.palette[0]
    @State private var symbol = "banknote.fill"
    @State private var autoPercent: Double = 0
    @State private var roundUp = 0
    @State private var confirmDelete = false

    let presets: [(String, String)] = [("Подушка безопасности", "shield.lefthalf.filled"), ("Отпуск", "airplane"), ("Новый телефон", "iphone"),
                                       ("Машина", "car.fill"), ("Ремонт", "hammer.fill"), ("Учёба", "graduationcap.fill"), ("Подарки", "gift.fill")]
    let symbols = ["banknote.fill", "shield.lefthalf.filled", "airplane", "iphone", "car.fill", "house.fill", "hammer.fill",
                   "graduationcap.fill", "gift.fill", "heart.fill", "gamecontroller.fill", "laptopcomputer", "bicycle", "pawprint.fill", "star.fill", "sparkles"]

    var body: some View {
        NavigationStack {
            Form {
                if goal == nil {
                    Section {
                        FlowLayout {
                            ForEach(presets.indices, id: \.self) { i in
                                Chip(title: presets[i].0, selected: name == presets[i].0) { pick(i) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    TextField("На что копим", text: $name)
                    LabeledContent("Сколько нужно") {
                        TextField("необязательно", text: $target).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Toggle("К определённой дате", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("Дата", selection: $deadline, displayedComponents: .date) }
                }
                Section {
                    Stepper(value: $autoPercent, in: 0...50, step: 5) {
                        HStack {
                            Text("С каждого дохода")
                            Spacer()
                            Text(autoPercent > 0 ? "\(Int(autoPercent))%" : "выкл").foregroundStyle(.secondary)
                        }
                    }
                    Picker("Сдача с трат", selection: $roundUp) {
                        Text("выкл").tag(0)
                        Text("до 10 ₽").tag(10)
                        Text("до 50 ₽").tag(50)
                        Text("до 100 ₽").tag(100)
                    }
                } header: { Text("Автоправила") } footer: {
                    Text("Процент с дохода: когда записываете зарплату или другой доход, часть сразу уходит в копилку. Сдача: трата 270 ₽ округляется до 300 ₽, а 30 ₽ откладываются сюда.")
                }
                Section("Значок и цвет") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(symbols, id: \.self) { s in
                            Image(systemName: s).font(.body).frame(width: 34, height: 34)
                                .foregroundStyle(symbol == s ? Color.white : Color(hex: hex))
                                .background(symbol == s ? Color(hex: hex) : Color(hex: hex).opacity(0.12), in: Circle())
                                .onTapGesture { symbol = s }
                        }
                    }
                    HStack {
                        ForEach(Theme.palette, id: \.self) { h in
                            Circle().fill(Color(hex: h)).frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: hex == h ? 2.5 : 0))
                                .onTapGesture { hex = h }
                        }
                    }
                }
                if let g = goal, !g.log.isEmpty {
                    Section("История") {
                        ForEach(Array(g.log.sorted { $0.date > $1.date }.prefix(30).enumerated()), id: \.offset) { _, e in
                            HStack {
                                Text(DF.short(e.date)).foregroundStyle(.secondary)
                                Spacer()
                                Text((e.amount >= 0 ? "+" : "−") + Fmt.rubU(e.amount)).foregroundStyle(e.amount >= 0 ? Theme.inc : Theme.exp)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                if goal != nil { Section { Button("Удалить копилку", role: .destructive) { confirmDelete = true } } }
            }
            .navigationTitle(goal == nil ? "Новая копилка" : "Копилка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .confirmationDialog("Удалить копилку? Накопленное останется на ваших счетах — удалится только учёт.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let g = goal { g.softDelete(); ctx.commit() }; dismiss() }
            }
            .onAppear(perform: load)
        }
    }

    private func pick(_ i: Int) {
        name = presets[i].0; symbol = presets[i].1
        if i == 0 {
            let c = Savings.cushionTarget(txs)
            if c > 0 { target = Fmt.input(c) }
            autoPercent = max(autoPercent, 10)
        }
    }

    private func load() {
        if let g = goal {
            name = g.name; target = g.target > 0 ? Fmt.input(g.target) : ""; hasDeadline = g.deadline != nil
            deadline = g.deadline ?? deadline; hex = g.hex; symbol = g.symbol; autoPercent = g.autoPercent; roundUp = g.roundUp
        } else {
            hex = Theme.palette[goals.count % Theme.palette.count]
            let c = UserDefaults.standard.double(forKey: "cushionPreset")
            if c > 0 {
                UserDefaults.standard.removeObject(forKey: "cushionPreset")
                pick(0)
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let t = parseAmount(target) ?? 0
        let g = goal ?? Goal(name: n, target: t, deadline: nil, hex: hex)
        g.name = n; g.target = max(0, t); g.deadline = hasDeadline ? deadline.noon : nil; g.hex = hex
        g.symbol = symbol; g.autoPercent = autoPercent; g.roundUp = roundUp
        if goal == nil { ctx.insert(g) }
        ctx.commit()
        dismiss()
    }
}

struct GoalAddSheet: View {
    let goal: Goal
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var router: Router
    @Query(sort: \Account.created) private var qAccs: [Account]
    private var accs: [Account] { qAccs.live }
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
                    if !take {
                        FlowLayout {
                            ForEach([500.0, 1000, 5000, 10000], id: \.self) { v in
                                Chip(title: "+" + Fmt.rubU(v), selected: false) { amount = Fmt.input((parseAmount(amount) ?? 0) + v) }
                            }
                        }
                    }
                } header: { Text(goal.target > 0 ? "В копилке \(Fmt.rubU(goal.saved)) из \(Fmt.rubU(goal.target))" : "В копилке \(Fmt.rubU(goal.saved))") }
                if !take { Section { Toggle("Учесть в расходах месяца", isOn: $toBudget) } footer: { Text("Включите, если хотите видеть отложенное в расходах — тогда остаток месяца будет честнее.") } }
                if let err { Section { Text(err).foregroundStyle(Theme.exp) } }
            }
            .navigationTitle(goal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(take ? "Взять" : "Положить", action: save).fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let v = parseAmount(amount), v > 0 else { err = "Введите сумму больше нуля."; return }
        let before = goal.saved
        if take && v > before { err = "В копилке только \(Fmt.rubU(before))."; return }
        var l = goal.log
        l.append(GoalEntry(date: Date().noon, amount: take ? -v : v))
        goal.log = l
        goal.dirty = true
        if !take && toBudget {
            let acc = accs.first { $0.uid.uuidString == lastAcc }?.uid ?? accs.first?.uid
            ctx.insert(Tx(kind: .exp, amount: v, cat: "savings", note: goal.name, date: Date(), accID: acc))
        }
        ctx.commit()
        dismiss()
        if !take && goal.target > 0 && before < goal.target && goal.saved >= goal.target {
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
                        ctx.commit()
                        Notifier.reschedule(ctx: ctx)
                        dismiss()
                    }
                }
            }
            .onChange(of: kind) { _, k in cat = Catalog.valid(cat, for: k) }
            .confirmationDialog("Удалить регулярный платёж?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let r = rec { r.softDelete(); ctx.commit() }; dismiss() }
            }
            .onAppear {
                if let r = rec { name = r.name; amount = Fmt.input(r.amount); kind = r.kind; cat = r.cat; day = r.day; yearly = r.yearly; month = r.month }
            }
        }
    }
}
