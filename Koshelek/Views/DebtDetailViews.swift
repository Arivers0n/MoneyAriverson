import SwiftUI
import SwiftData

// MARK: - Форма долга

struct DebtForm: View {
    let debt: Debt?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var router: Router

    @State private var type: DebtType = .credit
    @State private var dirIn = false
    @State private var name = ""
    @State private var lender = ""
    @State private var monthly = true
    @State private var total = ""
    @State private var payment = ""
    @State private var count = ""
    @State private var nTouched = false
    @State private var first = Date().addingMonths(1)
    @State private var rate = ""
    @State private var err: String?
    @State private var showScan = false
    @State private var scanning = false
    @State private var scanNote: String?

    var body: some View {
        NavigationStack {
            Form {
                if debt == nil {
                    Section {
                        Button { startScan() } label: {
                            HStack {
                                if scanning { ProgressView() } else { Image(systemName: "doc.viewfinder") }
                                Text(scanning ? "Claude читает график…" : (scanNote ?? "Заполнить по скриншоту графика"))
                            }
                            .font(.body.weight(.semibold))
                        }
                        .disabled(scanning)
                    } footer: { Text("Сделайте скриншот графика платежей в приложении банка — поля заполнятся сами.") }
                }
                Section("Вид") {
                    FlowLayout {
                        ForEach(DebtType.allCases) { t in
                            Chip(title: t.longName, color: t.color, selected: type == t) {
                                type = t
                                if t != .person { dirIn = false }
                                if debt == nil { monthly = !(t == .micro || t == .person) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    if type == .person {
                        Picker("Кто кому", selection: $dirIn) {
                            Text("Я должен").tag(false)
                            Text("Мне должны").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    TextField("Название, например «Кредит на машину»", text: $name)
                    TextField(type == .person ? (dirIn ? "Кто должен" : "Кому") : type.lenderLabel + " (\(type.placeholder))", text: $lender)
                }
                Section {
                    Picker("Как платить", selection: $monthly) {
                        Text("Каждый месяц").tag(true)
                        Text("Одним платежом").tag(false)
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Осталось вернуть") {
                        TextField("120 000", text: $total).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    if monthly {
                        LabeledContent("Платёж в месяц") {
                            TextField("8 500", text: $payment).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Платежей осталось") {
                            TextField("15", text: $count, onEditingChanged: { if $0 { nTouched = true } }).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                    }
                    DatePicker(monthly ? "Ближайший платёж" : "Вернуть до", selection: $first, displayedComponents: .date)
                    LabeledContent("Ставка, % годовых") {
                        TextField("необязательно", text: $rate).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Сумму и платёж берите из графика банка, вместе с процентами. Ставка нужна для калькулятора досрочки и совета, что гасить первым.")
                }
                if let err { Section { Text(err).foregroundStyle(Theme.exp) } }
            }
            .navigationTitle(debt == nil ? "Новый долг" : "Изменить долг")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).fontWeight(.semibold) }
            }
            .onChange(of: total) { _, _ in autoCount() }
            .onChange(of: payment) { _, _ in autoCount() }
            .scanFlow(isPresented: $showScan, title: "Скриншот графика платежей") { imgs in scan(imgs) }
            .onAppear(perform: load)
        }
    }

    private func autoCount() {
        guard !nTouched, let t = parseAmount(total), let p = parseAmount(payment), t > 0, p > 0 else { return }
        count = "\(Int(ceil(t / p - 1e-9)))"
    }

    private func load() {
        guard let d = debt else { return }
        type = d.type; dirIn = d.dirIn; name = d.name; lender = d.lender; monthly = d.n > 1
        total = Fmt.input(d.total); payment = d.n > 1 ? Fmt.input(d.payment) : ""; count = d.n > 1 ? "\(d.n)" : ""
        nTouched = true; first = d.first; rate = d.rate > 0 ? Fmt.input(d.rate) : ""
    }

    private func startScan() {
        guard Keychain.hasKey else { err = "Для скана нужен ключ Claude API — добавьте его в настройках."; return }
        showScan = true
    }

    private func scan(_ imgs: [Data]) {
        scanning = true; err = nil
        Task {
            defer { scanning = false }
            do {
                let d = try await Brain.parseDebt(imgs)
                type = d.type
                if !d.name.isEmpty { name = d.name }
                if !d.lender.isEmpty { lender = d.lender }
                monthly = d.n > 1
                total = Fmt.input((d.total * 100).rounded() / 100)
                if d.n > 1 { payment = Fmt.input((d.payment * 100).rounded() / 100); count = "\(d.n)"; nTouched = true }
                first = d.first
                if d.rate > 0 { rate = Fmt.input((d.rate * 100).rounded() / 100) }
                scanNote = "Заполнено — проверьте поля"
            } catch {
                err = error.localizedDescription
            }
        }
    }

    private func save() {
        guard let t = parseAmount(total), t > 0 else { err = "Укажите, сколько осталось вернуть."; return }
        var pay = t, n = 1
        if monthly {
            guard let p = parseAmount(payment), p > 0 else { err = "Укажите ежемесячный платёж."; return }
            pay = p
            n = Int(count) ?? Int(ceil(t / p))
            if n < 1 { n = Int(ceil(t / p)) }
            if n > 600 { err = "Слишком много платежей — проверьте сумму и платёж."; return }
        }
        let r = parseAmount(rate) ?? 0
        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty ? (type == .person ? (lender.isEmpty ? "Долг" : lender) : type.name) : name
        if let d = debt {
            d.type = type; d.dirIn = type == .person ? dirIn : false; d.name = finalName; d.lender = lender
            d.total = t; d.payment = pay; d.n = n; d.first = first.noon; d.rate = max(0, r)
        } else {
            ctx.insert(Debt(type: type, dirIn: type == .person ? dirIn : false, name: finalName, lender: lender, total: t, payment: pay, n: n, first: first, rate: max(0, r)))
        }
        ctx.commit()
        Notifier.reschedule(ctx: ctx)
        dismiss()
        router.say(debt == nil ? "Долг добавлен, график построен" : "Сохранено")
    }
}

// MARK: - Карточка долга

struct DebtDetail: View {
    @Bindable var debt: Debt
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var pay: PayTarget?
    @State private var edit = false
    @State private var confirmDelete = false
    @State private var extraText = ""

    var body: some View {
        let sch = debt.schedule()
        let okN = sch.filter { $0.st == .ok }.count, lateN = sch.filter { $0.st == .late }.count
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(debt.type == .person ? (debt.isOut ? "Я должен" : "Мне должны") : debt.type.name)
                            .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(debt.type.color, in: RoundedRectangle(cornerRadius: 6))
                        if !debt.lender.isEmpty { Text(debt.lender).foregroundStyle(.secondary) }
                    }
                    Bar(value: debt.progress, height: 12)
                    Text(debt.isClosed ? "Закрыт полностью" : "Выплачено \(Int((debt.progress * 100).rounded()))%" + (okN > 0 ? " · в срок: \(okN)" : "") + (lateN > 0 ? " · с опозданием: \(lateN)" : ""))
                        .font(.footnote).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        Stat(title: "Осталось", value: Fmt.rubU(debt.remaining))
                        Stat(title: "Выплачено", value: Fmt.rubU(debt.paidSum))
                        Stat(title: debt.n > 1 ? "Платёж в месяц" : "Разовый платёж", value: Fmt.rubU(debt.payment))
                        Stat(title: debt.rate > 0 ? "Ставка" : "Платежей", value: debt.rate > 0 ? "\(Fmt.input(debt.rate))%" : (debt.n > 1 ? "\(okN + lateN) из \(debt.n)" : "1"))
                    }
                    if !debt.isClosed {
                        HStack(spacing: 10) {
                            if let nx = debt.nextInst {
                                Button { pay = PayTarget(debt: debt, index: nx.i) } label: { Text("Внести платёж").frame(maxWidth: .infinity) }
                                    .buttonStyle(.borderedProminent).controlSize(.large)
                            }
                            Button { pay = PayTarget(debt: debt, index: -1) } label: { Text("Досрочно").frame(maxWidth: .infinity) }
                                .buttonStyle(.bordered).controlSize(.large)
                        }
                    }
                }
                .card()

                if !debt.isClosed && debt.n > 1 && debt.isOut { calculator }

                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle(text: "График платежей")
                    ForEach(sch) { x in
                        if x.st == .covered {
                            HStack {
                                Text("\(DF.short(x.due)) · платёж \(x.i + 1)")
                                Spacer()
                                Text("не нужен").foregroundStyle(.secondary)
                            }
                            .font(.subheadline).opacity(0.6).padding(.vertical, 8)
                        } else {
                            Button { pay = PayTarget(debt: debt, index: x.i) } label: { InstRow(x: x) }.buttonStyle(.plain)
                        }
                    }
                }
                .card()

                if !debt.extras.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(text: "Досрочные платежи")
                        ForEach(Array(debt.extras.enumerated()), id: \.offset) { j, e in
                            HStack {
                                Text(DF.short(e.date)).foregroundStyle(.secondary)
                                Text(Fmt.rubU(e.amount)).fontWeight(.semibold)
                                Spacer()
                                Button("Убрать", role: .destructive) {
                                    var ex = debt.extras
                                    ex.remove(at: j)
                                    debt.extras = ex
                                    ctx.commit()
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                    .card()
                }

                Button("Удалить долг", role: .destructive) { confirmDelete = true }.padding(.top, 4)
            }
            .padding(16)
        }
        .background(Backdrop())
        .navigationTitle(debt.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Изменить") { edit = true } }
        .sheet(item: $pay) { p in PaySheet(debt: p.debt, index: p.index) }
        .sheet(isPresented: $edit) { DebtForm(debt: debt) }
        .confirmationDialog("Удалить «\(debt.name)» вместе с графиком?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                debt.softDelete()
                ctx.commit()
                Notifier.reschedule(ctx: ctx)
                dismiss()
            }
        }
    }

    private var calculator: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Если платить больше")
            HStack {
                Text("Доплачивать")
                TextField("5 000", text: $extraText).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(maxWidth: 120)
                Text("₽ в месяц")
            }
            if let x = parseAmount(extraText), let r = extraPaymentEffect(debt, extra: x) {
                let gain = r.left - r.months
                if gain <= 0 {
                    Text("Почти не меняет срок — попробуйте сумму побольше.").font(.subheadline)
                } else {
                    Text("Закроете за **\(r.months) мес.** вместо \(r.left) — на \(gain) мес. раньше, примерно в \(DF.s(Date().addingMonths(r.months), "LLLL yyyy")).")
                        .font(.subheadline)
                    if let s = r.saved {
                        Text("Экономия на процентах ≈ **\(Fmt.rubU(s))**").font(.subheadline).foregroundStyle(Theme.inc)
                    } else {
                        Text("Укажите ставку в долге, чтобы посчитать экономию на процентах.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Расчёт примерный. При досрочке попросите банк уменьшить срок, а не платёж.").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Text("Введите сумму — покажу, насколько раньше закроете кредит.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

struct Stat: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Платёж

struct PaySheet: View {
    let debt: Debt
    let index: Int
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var router: Router
    @Query(sort: \Account.created) private var qAccs: [Account]
    private var accs: [Account] { qAccs.live }
    @AppStorage("lastAcc") private var lastAcc = ""

    @State private var amount = ""
    @State private var date = Date()
    @State private var late = false
    @State private var toBudget = true
    @State private var err: String?

    var inst: Inst? {
        guard index >= 0 else { return nil }
        return debt.schedule().first(where: { $0.i == index })
    }
    var isExtra: Bool { index < 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(text: $amount)
                } header: {
                    if let x = inst { Text("Срок \(DF.long(x.due)), по графику \(Fmt.rubU(x.plan))") }
                    else { Text("Осталось вернуть \(Fmt.rubU(debt.remaining))") }
                }
                Section {
                    DatePicker("Когда заплатил", selection: $date, displayedComponents: .date)
                        .onChange(of: date) { _, d in if let x = inst { late = d.day0 > x.due.day0 } }
                    if !isExtra {
                        Picker("Вовремя ли", selection: $late) {
                            Text("В срок").tag(false)
                            Text("С опозданием").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    if inst?.paid == nil {
                        Toggle(debt.isOut ? "Записать в бюджет как расход" : "Записать в бюджет как доход", isOn: $toBudget)
                    }
                }
                if let err { Section { Text(err).foregroundStyle(Theme.exp) } }
                if inst?.paid != nil {
                    Section { Button("Снять отметку об оплате", role: .destructive, action: undo) }
                }
            }
            .navigationTitle(isExtra ? "Досрочный платёж" : (debt.n > 1 ? "Платёж \(index + 1) из \(debt.n)" : "Платёж"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(inst?.paid != nil ? "Сохранить" : (isExtra ? "Внести" : "Оплачено"), action: save).fontWeight(.semibold)
                }
            }
            .onAppear {
                if let x = inst {
                    if let p = x.paid { amount = Fmt.input(p.amount); date = p.date; late = p.late }
                    else { amount = Fmt.input(min(x.plan, debt.remaining > 0 ? debt.remaining : x.plan)); date = Date(); late = Date().day0 > x.due.day0 }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let v = parseAmount(amount), v > 0 else { err = "Введите сумму больше нуля."; return }
        let before = debt.remaining
        let wasPaid = inst?.paid != nil
        if isExtra {
            var e = debt.extras
            e.append(ExtraPay(date: date.noon, amount: v))
            debt.extras = e
        } else {
            var p = debt.payments
            p[index] = Paid(date: date.noon, amount: v, late: late)
            debt.payments = p
        }
        if toBudget && !wasPaid {
            let acc = accs.first { $0.uid.uuidString == lastAcc }?.uid ?? accs.first?.uid
            ctx.insert(Tx(kind: debt.isOut ? .exp : .inc, amount: v, cat: debt.isOut ? "loans" : "debtback",
                          note: debt.name + (isExtra ? " · досрочно" : ""), date: date, accID: acc))
        }
        ctx.commit()
        Notifier.reschedule(ctx: ctx)
        dismiss()
        if before > 0 && debt.remaining <= 0 {
            router.celebrate = debt.isOut ? ("«\(debt.name)» закрыт!", "Долг полностью погашен. Так держать.") : ("«\(debt.name)» вам вернули!", "Долг полностью погашен.")
        } else {
            router.say(isExtra ? "Досрочный платёж внесён" : (late ? "Отмечено: с опозданием" : "Отмечено: оплачено в срок"))
        }
    }

    private func undo() {
        var p = debt.payments
        p.removeValue(forKey: index)
        debt.payments = p
        ctx.commit()
        Notifier.reschedule(ctx: ctx)
        dismiss()
    }
}
